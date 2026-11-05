import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:comic_reader_app/services/api_client.dart';
import 'package:comic_reader_app/services/app_logger.dart';
import 'package:comic_reader_app/services/sync_queue.dart';
import 'package:comic_reader_app/services/sync_queue_drainer.dart';

void main() {
  late Directory tempDir;
  late SyncQueue queue;

  setUp(() async {
    await AppLogger.init(logDirFactory: () async => null);
    tempDir = Directory.systemTemp.createTempSync('sync_drainer_test_');
    queue = SyncQueue(queuePath: '${tempDir.path}/sync_queue.json');
  });

  tearDown(() {
    AppLogger.resetForTest();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  ApiClient clientWith(Future<http.Response> Function(http.Request) handler) {
    return ApiClient(
      baseUrl: 'http://localhost:8080',
      deviceId: 'test',
      httpClient: MockClient(handler),
    );
  }

  Map<String, dynamic> progressEntry(String comicId, int page) => {
        'type': 'progress',
        'payload': {
          'comic_id': comicId,
          'current_page': page,
          'total_pages': 100,
        },
      };

  test('empty queue is a no-op', () async {
    final drainer = SyncQueueDrainer(
      queue: queue,
      client: clientWith((_) async => http.Response('{}', 200)),
    );
    await drainer.drain();
    expect(await queue.pendingCount, 0);
  });

  test('single entry that succeeds is removed', () async {
    await queue.enqueue(progressEntry('a', 1));
    final drainer = SyncQueueDrainer(
      queue: queue,
      client: clientWith((_) async => http.Response('{}', 200)),
    );
    await drainer.drain();
    expect(await queue.pendingCount, 0);
  });

  test('session entry is replayed and removed', () async {
    final captured = <http.Request>[];
    await queue.enqueue({
      'type': 'session',
      'payload': {
        'comic_id': 'c1',
        'series_id': 's1',
        'started_at': '2026-05-18T12:00:00.000Z',
        'pages_read': 10,
        'duration_s': 300,
      },
    });
    final drainer = SyncQueueDrainer(
      queue: queue,
      client: clientWith((req) async {
        captured.add(req);
        return http.Response('{}', 200);
      }),
    );
    await drainer.drain();
    expect(await queue.pendingCount, 0);
    expect(captured.length, 1);
    expect(captured.first.method, 'POST');
    expect(captured.first.url.path, '/reading/sessions');
  });

  test('entry returning 404 is dropped and drain continues', () async {
    await queue.enqueue(progressEntry('bad', 1));
    await queue.enqueue(progressEntry('good', 2));

    var callIndex = 0;
    final drainer = SyncQueueDrainer(
      queue: queue,
      client: clientWith((_) async {
        callIndex++;
        return callIndex == 1
            ? http.Response('not found', 404)
            : http.Response('{}', 200);
      }),
    );
    await drainer.drain();
    expect(await queue.pendingCount, 0);
    expect(callIndex, 2);
  });

  test('entry returning 500 breaks drain (entry stays at head)', () async {
    await queue.enqueue(progressEntry('a', 1));
    await queue.enqueue(progressEntry('b', 2));

    final drainer = SyncQueueDrainer(
      queue: queue,
      client: clientWith((_) async => http.Response('boom', 500)),
    );
    await drainer.drain();
    expect(await queue.pendingCount, 2);
    final remaining = await queue.readAll();
    expect(remaining.first['payload']['comic_id'], 'a');
  });

  for (final status in [401, 403]) {
    test('entry returning $status stays queued and stops the drain', () async {
      await queue.enqueue(progressEntry('a', 1));
      await queue.enqueue(progressEntry('b', 2));

      var calls = 0;
      final drainer = SyncQueueDrainer(
        queue: queue,
        client: clientWith((_) async {
          calls++;
          return http.Response('{"error":"unauthorized"}', status);
        }),
      );
      await drainer.drain();
      expect(calls, 1);
      expect(await queue.pendingCount, 2);
      final remaining = await queue.readAll();
      expect(remaining.first['payload']['comic_id'], 'a');
    });
  }

  test('entry throwing SocketException breaks drain', () async {
    await queue.enqueue(progressEntry('a', 1));
    await queue.enqueue(progressEntry('b', 2));

    final drainer = SyncQueueDrainer(
      queue: queue,
      client: clientWith((_) async {
        throw const SocketException('refused');
      }),
    );
    await drainer.drain();
    expect(await queue.pendingCount, 2);
  });

  test('replays progress with read_at from queued_at', () async {
    // Write directly to the queue file so we control queued_at precisely
    // (SyncQueue.enqueue always stamps DateTime.now()).
    const queuedAt = '2026-07-23T10:00:00.000Z';
    await File('${tempDir.path}/sync_queue.json').writeAsString(jsonEncode([
      {
        'type': 'progress',
        'payload': {'comic_id': 'a', 'current_page': 1, 'total_pages': 100},
        'queued_at': queuedAt,
      },
    ]));

    final captured = <http.Request>[];
    final drainer = SyncQueueDrainer(
      queue: queue,
      client: clientWith((req) async {
        captured.add(req);
        return http.Response('{}', 200);
      }),
    );
    await drainer.drain();

    expect(captured.length, 1);
    final body = jsonDecode(captured.first.body) as Map<String, dynamic>;
    expect(body['read_at'], DateTime.parse(queuedAt).millisecondsSinceEpoch);
  });

  test('replays queued bookmarks with a progress entry', () async {
    await queue.enqueue({
      'type': 'progress',
      'payload': {
        'comic_id': 'a',
        'current_page': 100,
        'total_pages': 100,
        'bookmarks': [
          {'id': '1', 'comic_id': 'a', 'page_num': 19},
        ],
      },
    });
    final captured = <http.Request>[];
    final drainer = SyncQueueDrainer(
      queue: queue,
      client: clientWith((req) async {
        captured.add(req);
        return http.Response('{}', 200);
      }),
    );
    await drainer.drain();

    final body = jsonDecode(captured.single.body) as Map<String, dynamic>;
    expect((body['bookmarks'] as List).map((b) => b['page_num']), [19]);
  });

  test('progress without chapters replays without a chapters field',
      () async {
    await queue.enqueue(progressEntry('a', 1));
    final captured = <http.Request>[];
    final drainer = SyncQueueDrainer(
      queue: queue,
      client: clientWith((req) async {
        captured.add(req);
        return http.Response('{}', 200);
      }),
    );
    await drainer.drain();

    final body = jsonDecode(captured.single.body) as Map<String, dynamic>;
    expect(body.containsKey('chapters'), isFalse);
  });

  test('409 drops entry and continues', () async {
    await queue.enqueue(progressEntry('stale', 1));
    await queue.enqueue(progressEntry('good', 2));

    var callIndex = 0;
    final drainer = SyncQueueDrainer(
      queue: queue,
      client: clientWith((_) async {
        callIndex++;
        return callIndex == 1
            ? http.Response('{"error":"stale progress write"}', 409)
            : http.Response('{}', 200);
      }),
    );
    await drainer.drain();

    expect(await queue.pendingCount, 0);
    expect(callIndex, 2);
  });

  test('mixed [good, bad-404, good] processes all three', () async {
    await queue.enqueue(progressEntry('good1', 1));
    await queue.enqueue(progressEntry('bad', 2));
    await queue.enqueue(progressEntry('good2', 3));

    var callIndex = 0;
    final drainer = SyncQueueDrainer(
      queue: queue,
      client: clientWith((_) async {
        callIndex++;
        if (callIndex == 2) return http.Response('not found', 404);
        return http.Response('{}', 200);
      }),
    );
    await drainer.drain();
    expect(await queue.pendingCount, 0);
    expect(callIndex, 3);
  });
  test('bubble_order entry replays as a PUT of the labels', () async {
    http.Request? sent;
    await queue.enqueue({
      'type': 'bubble_order',
      'payload': {'comic_id': 'c1', 'page': 4, 'labels': [2, 1]},
    });
    await SyncQueueDrainer(
      queue: queue,
      client: clientWith((req) async {
        sent = req;
        return http.Response('', 204);
      }),
    ).drain();
    expect(sent!.method, 'PUT');
    expect(sent!.url.path, '/comics/c1/pages/4/bubbles/order');
    expect(jsonDecode(sent!.body), {'labels': [2, 1]});
    expect(await queue.pendingCount, 0);
  });
}
