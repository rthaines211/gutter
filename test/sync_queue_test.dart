import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/services/sync_queue.dart';

void main() {
  late Directory tempDir;
  late SyncQueue queue;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('sync_queue_test_');
    queue = SyncQueue(queuePath: '${tempDir.path}/sync_queue.json');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('enqueue adds entry and readAll returns it', () async {
    await queue.enqueue({
      'type': 'progress',
      'payload': {'comic_id': 'abc', 'current_page': 5},
    });
    final entries = await queue.readAll();
    expect(entries.length, 1);
    expect(entries[0]['type'], 'progress');
    expect(entries[0]['payload']['comic_id'], 'abc');
    expect(entries[0].containsKey('queued_at'), isTrue);
  });

  test('enqueue appends to existing entries', () async {
    await queue.enqueue({'type': 'progress', 'payload': {}});
    await queue.enqueue({'type': 'session', 'payload': {}});
    final entries = await queue.readAll();
    expect(entries.length, 2);
    expect(entries[0]['type'], 'progress');
    expect(entries[1]['type'], 'session');
  });

  test('readAll returns empty list when no queue file', () async {
    final entries = await queue.readAll();
    expect(entries, isEmpty);
  });

  test('clear removes all entries', () async {
    await queue.enqueue({'type': 'progress', 'payload': {}});
    await queue.enqueue({'type': 'session', 'payload': {}});
    await queue.clear();
    final entries = await queue.readAll();
    expect(entries, isEmpty);
  });

  test('pendingCount returns correct count', () async {
    expect(await queue.pendingCount, 0);
    await queue.enqueue({'type': 'progress', 'payload': {}});
    await queue.enqueue({'type': 'session', 'payload': {}});
    expect(await queue.pendingCount, 2);
  });

  test('removeFirst removes oldest entry', () async {
    await queue.enqueue({'type': 'progress', 'payload': {'n': 1}});
    await queue.enqueue({'type': 'session', 'payload': {'n': 2}});
    await queue.removeFirst();
    final entries = await queue.readAll();
    expect(entries.length, 1);
    expect(entries[0]['payload']['n'], 2);
  });

  test('corrupt queue file reads as empty instead of throwing', () async {
    // Regression: a FormatException here propagated out of SyncQueueDrainer
    // into SyncEngine._sync(), which aborted before its /sync pull — wedging
    // all syncing permanently and silently.
    File('${tempDir.path}/sync_queue.json')
        .writeAsStringSync('[{"type":"progress"}]\u0000\u0000');
    expect(await queue.readAll(), isEmpty);
    expect(await queue.pendingCount, 0);
  });

  test('corrupt queue file self-heals on next enqueue', () async {
    File('${tempDir.path}/sync_queue.json').writeAsStringSync('not json');
    await queue.enqueue({'type': 'progress', 'payload': {'n': 1}});
    final entries = await queue.readAll();
    expect(entries.length, 1);
    expect(entries[0]['payload']['n'], 1);
  });

  test('non-map entries are dropped rather than throwing on iteration', () async {
    File('${tempDir.path}/sync_queue.json')
        .writeAsStringSync('[{"type":"progress","payload":{}},"junk",42]');
    final entries = await queue.readAll();
    expect(entries.length, 1);
    expect(entries[0]['type'], 'progress');
  });
}
