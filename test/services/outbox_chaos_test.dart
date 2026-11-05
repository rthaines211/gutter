import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:comic_reader_app/services/api_client.dart';
import 'package:comic_reader_app/services/app_logger.dart';
import 'package:comic_reader_app/services/sync_queue.dart';
import 'package:comic_reader_app/services/sync_queue_drainer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// The outbox holds writes the server hasn't seen yet — mostly reading
/// progress, which can't be recovered if dropped. These tests throw races,
/// flaky responses and bad entries at it and check nothing is lost.
void main() {
  late Directory tempDir;
  late String path;

  setUp(() async {
    await AppLogger.init(logDirFactory: () async => null);
    tempDir = Directory.systemTemp.createTempSync('outbox_chaos_');
    path = '${tempDir.path}/sync_queue.json';
  });

  tearDown(() {
    AppLogger.resetForTest();
    tempDir.deleteSync(recursive: true);
  });

  Map<String, dynamic> progress(String id) => {
        'type': 'progress',
        'payload': {'comic_id': id, 'current_page': 1, 'total_pages': 10},
      };

  List<String> ids(List<Map<String, dynamic>> entries) =>
      [for (final e in entries) (e['payload'] as Map)['comic_id'] as String];

  ApiClient client(Future<http.Response> Function(http.Request) h) =>
      ApiClient(baseUrl: 'http://x', deviceId: 't', httpClient: MockClient(h));

  test('concurrent enqueues all land', () async {
    final q = SyncQueue(queuePath: path);
    await Future.wait([for (var i = 0; i < 40; i++) q.enqueue(progress('c$i'))]);
    expect((await q.readAll()).length, 40);
  });

  test('enqueue racing removeFirst on another instance keeps the new entry',
      () async {
    await SyncQueue(queuePath: path).enqueue(progress('a'));
    // Provider rebuilds hand out fresh instances for the same file.
    await Future.wait([
      SyncQueue(queuePath: path).removeFirst(),
      SyncQueue(queuePath: path).enqueue(progress('b')),
    ]);
    expect(ids(await SyncQueue(queuePath: path).readAll()), ['b']);
  });

  test('a malformed entry is dropped, not a permanent block', () async {
    final q = SyncQueue(queuePath: path);
    await q.enqueue({
      'type': 'progress',
      'payload': {'comic_id': null, 'current_page': 'x'},
    });
    await q.enqueue(progress('good'));
    final sent = <String>[];
    await SyncQueueDrainer(
      queue: q,
      client: client((r) async {
        sent.add(r.url.path);
        return http.Response('{}', 200);
      }),
    ).drain();
    expect(sent, ['/reading/good']);
    expect(await q.readAll(), isEmpty);
  });

  for (final status in [408, 429]) {
    test('$status is retried, not dropped', () async {
      final q = SyncQueue(queuePath: path);
      await q.enqueue(progress('a'));
      await SyncQueueDrainer(
        queue: q,
        client: client((_) async => http.Response('{"error":"slow"}', status)),
      ).drain();
      expect(ids(await q.readAll()), ['a']);
    });
  }

  test('chaos: flaky server + writes during drains lose nothing', () async {
    final rnd = Random(42);
    final delivered = <String>{};
    var healthy = false;
    final flaky = client((r) async {
      await Future<void>.delayed(Duration(microseconds: rnd.nextInt(500)));
      if (!healthy) {
        switch (rnd.nextInt(4)) {
          case 0:
            throw const SocketException('down');
          case 1:
            return http.Response('{"error":"boom"}', 500);
          case 2:
            throw TimeoutException('slow');
        }
      }
      delivered.add(r.url.pathSegments.last);
      return http.Response(jsonEncode({}), 200);
    });

    final written = <String>[];
    for (var round = 0; round < 30; round++) {
      final writes = [
        for (var i = 0; i < 3; i++)
          () {
            final id = 'r${round}_$i';
            written.add(id);
            return SyncQueue(queuePath: path).enqueue(progress(id));
          }(),
      ];
      await Future.wait([
        SyncQueueDrainer(queue: SyncQueue(queuePath: path), client: flaky)
            .drain(),
        ...writes,
      ]);
    }
    healthy = true;
    await SyncQueueDrainer(queue: SyncQueue(queuePath: path), client: flaky)
        .drain();

    expect(await SyncQueue(queuePath: path).readAll(), isEmpty);
    expect(delivered, containsAll(written));
  });
}
