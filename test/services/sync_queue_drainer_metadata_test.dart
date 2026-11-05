import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:comic_reader_app/services/api_client.dart';
import 'package:comic_reader_app/services/sync_queue.dart';
import 'package:comic_reader_app/services/sync_queue_drainer.dart';
import 'package:comic_reader_app/services/app_logger.dart';

void main() {
  late Directory tmp;
  late SyncQueue queue;
  late List<http.Request> requests;

  setUp(() async {
    await AppLogger.init(logDirFactory: () async => null);
    tmp = Directory.systemTemp.createTempSync('drainer_metadata_test');
    queue = SyncQueue(queuePath: '${tmp.path}/sync_queue.json');
    requests = [];
  });

  tearDown(() {
    AppLogger.resetForTest();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  ApiClient okClient() => ApiClient(
        baseUrl: 'http://x',
        deviceId: 't',
        httpClient: MockClient((req) async {
          requests.add(req);
          return http.Response('', 204);
        }),
      );

  test('replays comic_metadata entries', () async {
    await queue.enqueue({
      'type': 'comic_metadata',
      'payload': {'comic_id': 'c1', 'fields': {'title': 'T'}},
    });

    await SyncQueueDrainer(queue: queue, client: okClient()).drain();

    expect((await queue.pendingCount), 0);
    expect(requests, hasLength(1));
    expect(requests[0].method, 'PATCH');
    expect(requests[0].url.path, '/comics/c1/metadata');
    expect(jsonDecode(requests[0].body), {'title': 'T'});
  });

  test('replays series_metadata entries', () async {
    await queue.enqueue({
      'type': 'series_metadata',
      'payload': {'series_id': 's1', 'fields': {'publisher': 'P'}},
    });

    await SyncQueueDrainer(queue: queue, client: okClient()).drain();

    expect((await queue.pendingCount), 0);
    expect(requests, hasLength(1));
    expect(requests[0].method, 'PATCH');
    expect(requests[0].url.path, '/series/s1/metadata');
    expect(jsonDecode(requests[0].body), {'publisher': 'P'});
  });

  test('replays both comic and series metadata entries', () async {
    await queue.enqueue({
      'type': 'comic_metadata',
      'payload': {'comic_id': 'c1', 'fields': {'title': 'T'}},
    });
    await queue.enqueue({
      'type': 'series_metadata',
      'payload': {'series_id': 's1', 'fields': {'publisher': 'P'}},
    });

    await SyncQueueDrainer(queue: queue, client: okClient()).drain();

    expect((await queue.pendingCount), 0);
    expect(requests, hasLength(2));
    expect(requests[0].url.path, '/comics/c1/metadata');
    expect(requests[1].url.path, '/series/s1/metadata');
  });

  test('4xx drops metadata entry and continues', () async {
    await queue.enqueue({
      'type': 'comic_metadata',
      'payload': {'comic_id': 'c1', 'fields': {'title': 'T'}},
    });

    final client = ApiClient(
      baseUrl: 'http://x',
      deviceId: 't',
      httpClient: MockClient((req) async {
        requests.add(req);
        return http.Response('', 409);
      }),
    );

    await SyncQueueDrainer(queue: queue, client: client).drain();

    expect((await queue.pendingCount), 0);
    expect(requests, hasLength(1));
  });

  test('5xx breaks and keeps metadata entry', () async {
    await queue.enqueue({
      'type': 'series_metadata',
      'payload': {'series_id': 's1', 'fields': {'publisher': 'P'}},
    });

    final client = ApiClient(
      baseUrl: 'http://x',
      deviceId: 't',
      httpClient: MockClient((req) async {
        requests.add(req);
        return http.Response('', 500);
      }),
    );

    await SyncQueueDrainer(queue: queue, client: client).drain();

    expect((await queue.pendingCount), 1);
    expect(requests, hasLength(1));
  });
}
