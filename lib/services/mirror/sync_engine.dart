import 'dart:async';

import '../api_client.dart';
import '../sync_queue.dart';
import '../sync_queue_drainer.dart';
import 'mirror_database.dart';

/// Push-then-pull sync: flush the outbox queue so the server has our writes,
/// then pull the delta and apply it. Progress entries still queued after the
/// flush are protected from being overwritten by the pull.
///
/// Errors propagate to the caller; retry rides the existing connectivity
/// poll / lifecycle triggers, so no internal backoff timer is needed.
class SyncEngine {
  final MirrorDatabase db;
  final ApiClient client;
  final SyncQueue queue;

  Future<void>? _inFlight;
  bool _followUpRequested = false;

  SyncEngine({required this.db, required this.client, required this.queue});

  /// Public for tests only.
  Future<void>? get inFlightForTesting => _inFlight;

  Future<void> sync() {
    if (_inFlight != null) {
      // A sync that's already past its pull can't see writes made after it
      // started; remember to run once more so callers' mutations land.
      _followUpRequested = true;
      return _inFlight!;
    }
    _inFlight = _sync().whenComplete(() {
      _inFlight = null;
      if (_followUpRequested) {
        _followUpRequested = false;
        unawaited(sync().catchError((_) {}));
      }
    });
    return _inFlight!;
  }

  Future<void> _sync() async {
    await SyncQueueDrainer(queue: queue, client: client).drain();

    final pending = <String>{};
    final pendingQueues = <String>{};
    final pendingSeries = <String>{};
    for (final entry in await queue.readAll()) {
      final payload = entry['payload'] as Map<String, dynamic>?;
      switch (entry['type']) {
        case 'progress':
          final comicId = payload?['comic_id'] as String?;
          if (comicId != null) pending.add(comicId);
        case 'queue_upsert':
          final id = payload?['id'] as String?;
          if (id != null) pendingQueues.add(id);
        case 'comic_metadata':
          // Protect the issue payload from being overwritten by a pull while
          // the PATCH is still pending in the outbox.
          final comicId = payload?['comic_id'] as String?;
          if (comicId != null) pending.add(comicId);
        case 'series_metadata':
          // Protect the series payload from being overwritten by a pull while
          // the PATCH is still pending in the outbox.
          final seriesId = payload?['series_id'] as String?;
          if (seriesId != null) pendingSeries.add(seriesId);
      }
    }

    final since =
        int.tryParse(await db.getSyncState('last_server_time') ?? '') ?? 0;
    final resp = await client.fetchSync(since: since);
    await db.applySync(resp,
        protectedComicIds: pending,
        protectedQueueIds: pendingQueues,
        protectedSeriesIds: pendingSeries);
    await db.setSyncState('last_server_time', resp.serverTime.toString());

    await _healMissingSeries(resp.seriesIds);
  }

  /// Delta sync only inserts the *changed* set, but the keep-list
  /// (`series_ids`) may reference series whose `updated_at` predates our
  /// watermark and which are absent from the mirror (e.g. added while a sync
  /// was failing). Such a series is never pruned (it's in the keep-list) yet
  /// never inserted, so it stays invisible to mirror-backed views and its
  /// detail page fails with "not in local mirror". Backfill any keep-list ids
  /// missing locally by fetching each and inserting it.
  Future<void> _healMissingSeries(List<String> keepIds) async {
    if (keepIds.isEmpty) return;
    final localIds = await db.allSeriesIds();
    final missing = keepIds.toSet().difference(localIds);
    if (missing.isEmpty) return;

    final healed = <Map<String, dynamic>>[];
    for (final id in missing) {
      try {
        healed.add(await client.fetchSeriesRaw(id));
      } catch (_) {
        // One unreachable/removed id must not abort the batch; a later sync
        // retries the rest.
      }
    }
    await db.healMissingSeries(healed);
  }
}
