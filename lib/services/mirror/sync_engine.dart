import 'dart:async';

import '../api_client.dart';
import '../sync_queue.dart';
import '../sync_queue_drainer.dart';
import 'mirror_database.dart';
import 'sync_progress.dart';

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

  /// Komga has no delta endpoint, so every pull re-reads the whole library:
  /// within this long of the last pull, only explicit (`force`) syncs pull;
  /// the rest just push the outbox.
  final Duration minPullInterval;

  Future<void>? _inFlight;
  bool _followUpRequested = false;
  bool _forceFollowUp = false;
  DateTime? _lastPull;

  /// Progress for the sync UI; reporting only, never changes the sync.
  final SyncProgressUpdate? onProgress;

  SyncEngine({
    required this.db,
    required this.client,
    required this.queue,
    this.minPullInterval = Duration.zero,
    this.onProgress,
  });

  void _report(SyncProgress Function(SyncProgress) f) => onProgress?.call(f);

  /// Public for tests only.
  Future<void>? get inFlightForTesting => _inFlight;

  /// [force]: a refresh the user asked for; always pulls.
  Future<void> sync({bool force = false}) {
    if (_inFlight != null) {
      // A sync that's already past its pull can't see writes made after it
      // started; remember to run once more so callers' mutations land.
      _followUpRequested = true;
      _forceFollowUp |= force;
      return _inFlight!;
    }
    _inFlight = _sync(force).whenComplete(() {
      _inFlight = null;
      if (_followUpRequested) {
        final force = _forceFollowUp;
        _followUpRequested = _forceFollowUp = false;
        unawaited(sync(force: force).catchError((_) {}));
      }
    });
    return _inFlight!;
  }

  Future<void> _sync(bool force) async {
    _report((_) => SyncProgress.start());
    try {
      await _pushThenPull(force);
      _report((p) => p.next(stage: SyncStage.done));
    } catch (e) {
      _report((p) => p.next(stage: SyncStage.failed, error: e));
      rethrow;
    }
  }

  Future<void> _pushThenPull(bool force) async {
    await SyncQueueDrainer(queue: queue, client: client).drain();
    final last = _lastPull;
    if (!force &&
        last != null &&
        DateTime.now().difference(last) < minPullInterval) {
      return;
    }

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
    _report((p) => p.next(stage: SyncStage.fetching, initial: since == 0));
    final resp = await client.fetchSync(
        since: since,
        onSeries: (done, total) =>
            _report((p) => p.next(seriesDone: done, seriesTotal: total)));
    _report((p) => p.next(
        stage: SyncStage.applying,
        seriesTotal: p.seriesTotal ?? resp.series.length));
    await db.applySync(resp,
        protectedComicIds: pending,
        protectedQueueIds: pendingQueues,
        protectedSeriesIds: pendingSeries);
    await db.setSyncState('last_server_time', resp.serverTime.toString());
    _lastPull = DateTime.now();
    _report((p) => p.next(seriesDone: p.seriesTotal));

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
