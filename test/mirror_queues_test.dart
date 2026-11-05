import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/models/reading_queue.dart';
import 'package:comic_reader_app/models/sync_response.dart';
import 'package:comic_reader_app/services/mirror/mirror_database.dart';

MirrorDatabase _memDb() => MirrorDatabase(NativeDatabase.memory());

ReadingQueue _q(String id, String name, List<String> series, {int pos = 0}) =>
    ReadingQueue(
      id: id,
      name: name,
      position: pos,
      seriesIds: series,
      createdAt: DateTime.utc(2026, 6, 16),
      updatedAt: DateTime.utc(2026, 6, 16),
    );

void main() {
  test('upsertQueueLocal + watchQueues preserves order', () async {
    final db = _memDb();
    addTearDown(db.close);

    await db.upsertQueueLocal(_q('q1', 'A', ['a', 'b'], pos: 0));
    await db.upsertQueueLocal(_q('q2', 'B', [], pos: 1));

    final queues = await db.watchQueues().first;
    expect(queues.map((q) => q.id), ['q1', 'q2']);
    expect(queues[0].seriesIds, ['a', 'b']);
    expect(queues[1].seriesIds, isEmpty);
  });

  test('upsertQueueLocal replaces membership', () async {
    final db = _memDb();
    addTearDown(db.close);
    await db.upsertQueueLocal(_q('q1', 'A', ['a', 'b', 'c']));
    await db.upsertQueueLocal(_q('q1', 'A', ['c', 'a']));
    final queues = await db.watchQueues().first;
    expect(queues.single.seriesIds, ['c', 'a']);
  });

  test('deleteQueueLocal removes queue and items', () async {
    final db = _memDb();
    addTearDown(db.close);
    await db.upsertQueueLocal(_q('q1', 'A', ['a']));
    await db.deleteQueueLocal('q1');
    expect(await db.watchQueues().first, isEmpty);
  });

  test('applySync upserts queues and prunes by queue_ids', () async {
    final db = _memDb();
    addTearDown(db.close);
    await db.upsertQueueLocal(_q('stale', 'Stale', ['x']));

    final resp = SyncResponse(
      serverTime: 1000,
      series: const [],
      progress: const [],
      seriesIds: const [],
      progressIds: const [],
      queues: [
        {
          'id': 'q1',
          'name': 'Weekend',
          'icon': 'star',
          'color': '#FFD700',
          'position': 0,
          'series_ids': ['batman'],
          'created_at': '2026-06-16T12:00:00Z',
          'updated_at': '2026-06-16T12:00:00Z',
        },
      ],
      queueIds: const ['q1'],
    );
    await db.applySync(resp);

    final queues = await db.watchQueues().first;
    expect(queues.map((q) => q.id), ['q1']);
    expect(queues.single.seriesIds, ['batman']);
  });

  test('applySync protects queue ids still in the outbox', () async {
    final db = _memDb();
    addTearDown(db.close);
    await db.upsertQueueLocal(_q('local', 'Local', ['y']));

    final resp = SyncResponse(
      serverTime: 1000,
      series: const [],
      progress: const [],
      seriesIds: const [],
      progressIds: const [],
      queues: const [],
      queueIds: const [],
    );
    await db.applySync(resp, protectedQueueIds: {'local'});

    final queues = await db.watchQueues().first;
    expect(queues.map((q) => q.id), ['local']);
  });

  test('autoRemoveOnComplete removes a fully-read series from all queues',
      () async {
    final db = _memDb();
    addTearDown(db.close);

    // Seed a series with two issues via applySync (issues live in issue_rows).
    await db.applySync(SyncResponse(
      serverTime: 1,
      series: [
        {
          'id': 's1',
          'name': 'Saga',
          'updated_at': '2026-06-16T12:00:00Z',
          'issues': [
            {'id': 'i1'},
            {'id': 'i2'},
          ],
        }
      ],
      progress: const [],
      seriesIds: const ['s1'],
      progressIds: const [],
      queueIds: const [],
    ));
    await db.upsertQueueLocal(_q('q1', 'A', ['s1', 's2']));

    // Only one issue read -> not complete -> no removal.
    await db.saveProgressLocal(comicId: 'i1', currentPage: 10, totalPages: 10);
    var changed = await db.autoRemoveOnComplete('i1');
    expect(changed, isEmpty);
    expect((await db.watchQueues().first).single.seriesIds, ['s1', 's2']);

    // Second issue read -> series complete -> removed from queue.
    await db.saveProgressLocal(comicId: 'i2', currentPage: 8, totalPages: 8);
    changed = await db.autoRemoveOnComplete('i2');
    expect(changed.map((q) => q.id), ['q1']);
    expect((await db.watchQueues().first).single.seriesIds, ['s2']);
  });
}
