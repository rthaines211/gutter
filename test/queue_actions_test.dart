import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/providers/queue_provider.dart';
import 'package:comic_reader_app/services/mirror/mirror_database.dart';
import 'package:comic_reader_app/services/sync_queue.dart';

void main() {
  test('create then addSeries persists to the mirror and outbox', () async {
    final db = MirrorDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final dir = Directory.systemTemp.createTempSync('qact');
    addTearDown(() => dir.deleteSync(recursive: true));
    final outbox = SyncQueue(queuePath: '${dir.path}/q.json');

    final actions = QueueActions(db: db, outbox: outbox, syncEngine: null);

    final q = await actions.create('Weekend');
    await actions.addSeries(q, 'batman');

    final queues = await db.watchQueues().first;
    expect(queues.single.name, 'Weekend');
    expect(queues.single.seriesIds, ['batman']);

    expect(await outbox.pendingCount, greaterThanOrEqualTo(1));
  });

  test('removeSeries drops the series locally', () async {
    final db = MirrorDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final dir = Directory.systemTemp.createTempSync('qact2');
    addTearDown(() => dir.deleteSync(recursive: true));
    final outbox = SyncQueue(queuePath: '${dir.path}/q.json');
    final actions = QueueActions(db: db, outbox: outbox, syncEngine: null);

    var q = await actions.create('A');
    await actions.addSeries(q, 'a');
    q = (await db.watchQueues().first).single;
    await actions.removeSeries(q, 'a');

    expect((await db.watchQueues().first).single.seriesIds, isEmpty);
  });
}
