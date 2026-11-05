import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/reading_queue.dart';
import '../services/mirror/mirror_database.dart';
import '../services/mirror/sync_engine.dart';
import '../services/sync_queue.dart';
import 'cache_providers.dart';
import 'mirror_provider.dart';

/// Live stream of all queues from the mirror (ordered, offline-capable).
final queuesProvider = StreamProvider<List<ReadingQueue>>((ref) {
  return ref.watch(mirrorDbProvider).watchQueues();
});

final queueActionsProvider = Provider<QueueActions>((ref) {
  return QueueActions(
    db: ref.watch(mirrorDbProvider),
    outbox: ref.watch(syncQueueProvider),
    syncEngine: ref.watch(syncEngineProvider),
  );
});

/// Local-first queue mutations: write the mirror, enqueue a snapshot to the
/// outbox, then nudge a sync to push it. Mirrors the progress-write pattern.
class QueueActions {
  final MirrorDatabase db;
  final SyncQueue? outbox;
  final SyncEngine? syncEngine;

  QueueActions({
    required this.db,
    required this.outbox,
    required this.syncEngine,
  });

  static String newId() =>
      'q_${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(0x7fffffff)}';

  Future<void> _commit(ReadingQueue q) async {
    await db.upsertQueueLocal(q);
    await outbox?.enqueue({'type': 'queue_upsert', 'payload': q.toSyncJson()});
    unawaited(syncEngine?.sync().catchError((_) {}));
  }

  Future<ReadingQueue> create(String name) async {
    final existing = await db.watchQueues().first;
    final nextPos = existing.isEmpty
        ? 0
        : existing.map((q) => q.position).reduce(max) + 1;
    final now = DateTime.now();
    final q = ReadingQueue(
      id: newId(),
      name: name,
      position: nextPos,
      createdAt: now,
      updatedAt: now,
    );
    await _commit(q);
    return q;
  }

  Future<void> rename(ReadingQueue q, String name) =>
      _commit(q.copyWith(name: name, updatedAt: DateTime.now()));

  Future<void> delete(ReadingQueue q) async {
    await db.deleteQueueLocal(q.id);
    await outbox?.enqueue({
      'type': 'queue_delete',
      'payload': {'id': q.id},
    });
    unawaited(syncEngine?.sync().catchError((_) {}));
  }

  Future<void> addSeries(ReadingQueue q, String seriesId) {
    if (q.seriesIds.contains(seriesId)) return Future.value();
    return _commit(
      q.copyWith(
        seriesIds: [...q.seriesIds, seriesId],
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<void> removeSeries(ReadingQueue q, String seriesId) => _commit(
    q.copyWith(
      seriesIds: q.seriesIds.where((s) => s != seriesId).toList(),
      updatedAt: DateTime.now(),
    ),
  );

  Future<void> reorder(ReadingQueue q, List<String> newOrder) =>
      _commit(q.copyWith(seriesIds: newOrder, updatedAt: DateTime.now()));
}
