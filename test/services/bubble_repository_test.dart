import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:comic_reader_app/models/page_bubbles.dart';
import 'package:comic_reader_app/services/api_client.dart';
import 'package:comic_reader_app/services/app_logger.dart';
import 'package:comic_reader_app/services/bubble_repository.dart';
import 'package:comic_reader_app/services/mirror/mirror_database.dart';
import 'package:comic_reader_app/services/sync_queue.dart';

Map<String, dynamic> sidecar(List<int> labels) => {
  'v': 1,
  'w': 100,
  'h': 100,
  'bubbles': [
    for (final l in labels)
      {
        'r': [l, l, 5, 5],
        'label': l,
      },
  ],
};

void main() {
  late Directory tmp;
  late SyncQueue queue;
  final requests = <http.Request>[];

  setUp(() async {
    await AppLogger.init(
      logDirFactory: () async => null,
    ); // ApiClient logs every request
    tmp = Directory.systemTemp.createTempSync('bubble_repo_');
    queue = SyncQueue(queuePath: p.join(tmp.path, 'q.json'));
    requests.clear();
  });
  tearDown(() {
    AppLogger.resetForTest();
    tmp.deleteSync(recursive: true);
  });

  BubbleRepository repo(Future<http.Response> Function(http.Request) handler) =>
      BubbleRepository(
        client: ApiClient(
          baseUrl: 'http://x',
          deviceId: 't',
          httpClient: MockClient((r) {
            requests.add(r);
            return handler(r);
          }),
        ),
        queue: queue,
      );

  test('fetches from the server and caches, including 404', () async {
    final r = repo(
      (req) async => req.url.path.endsWith('/pages/0/bubbles')
          ? http.Response(jsonEncode(sidecar([1, 2])), 200)
          : http.Response('not processed', 404),
    );
    expect((await r.forPage('c1', 0))!.labels, [1, 2]);
    expect(await r.forPage('c1', 1), isNull);
    await r.forPage('c1', 0);
    await r.forPage('c1', 1);
    expect(requests, hasLength(2));
  });

  test('network errors are not cached', () async {
    var fail = true;
    final r = repo((req) async {
      if (fail) throw const SocketException('offline');
      return http.Response(jsonEncode(sidecar([1])), 200);
    });
    expect(await r.forPage('c1', 0), isNull);
    fail = false;
    expect((await r.forPage('c1', 0))!.labels, [1]);
  });

  test('downloaded bubbles.json wins over the network', () async {
    File(p.join(tmp.path, 'bubbles.json')).writeAsStringSync(
      jsonEncode({
        'pages': {
          '3': sidecar([7]),
        },
      }),
    );
    final r = repo((req) async => http.Response('', 500))..localDir = tmp.path;
    expect((await r.forPage('c1', 3))!.labels, [7]);
    expect(await r.forPage('c1', 4), isNull);
    expect(requests, isEmpty);
  });

  test('saveOrder PUTs labels and keeps the order for offline rereads', () async {
    final big = File(p.join(tmp.path, 'bubbles.json'))
      ..writeAsStringSync(
        jsonEncode({
          'pages': {
            '0': sidecar([1, 2, 3]),
          },
        }),
      );
    final before = big.readAsStringSync();
    final r = repo((req) async => http.Response('', 204))..localDir = tmp.path;
    final pb = (await r.forPage('c1', 0))!..swapWithNext(0);
    await r.saveOrder('c1', 0, pb);
    expect(requests.single.method, 'PUT');
    expect(requests.single.url.path, '/comics/c1/pages/0/bubbles/order');
    expect(jsonDecode(requests.single.body), {
      'labels': [2, 1, 3],
    });
    expect(await queue.pendingCount, 0);
    // The big sidecar file is never rewritten (it can be ~23 MB); a reopened reader still sees the order.
    expect(big.readAsStringSync(), before);
    final reopened = repo((req) async => http.Response('', 500))
      ..localDir = tmp.path;
    expect((await reopened.forPage('c1', 0))!.labels, [2, 1, 3]);
  });

  test('a malformed sidecar reads as not processed, once', () async {
    final r = repo((req) async => http.Response('{"v":1,"w":"x"}', 200));
    expect(await r.forPage('c1', 0), isNull);
    expect(await r.forPage('c1', 0), isNull);
    expect(requests, hasLength(1));
  });

  test('one failed save does not stop later saves', () async {
    final pb = PageBubbles.fromJson(sidecar([1, 2]));
    var offline = true;
    final r = BubbleRepository(
      client: ApiClient(
        baseUrl: 'http://x',
        deviceId: 't',
        httpClient: MockClient((req) async {
          requests.add(req);
          if (offline) throw const SocketException('offline');
          return http.Response('', 204);
        }),
      ),
      queue: _ThrowingQueue(p.join(tmp.path, 'q2.json')),
    );
    await r.saveOrder('c1', 0, pb).catchError((_) {});
    offline = false;
    await r.saveOrder('c1', 0, pb);
    expect(requests.where((q) => q.method == 'PUT'), hasLength(2));
  });

  test('saveOrder queues when offline, drops a 4xx', () async {
    final pb = PageBubbles.fromJson(sidecar([1, 2]));
    await repo(
      (req) async => throw const SocketException('offline'),
    ).saveOrder('c1', 0, pb);
    final entries = await queue.readAll();
    expect(entries.single['type'], 'bubble_order');
    expect(entries.single['payload'], {
      'comic_id': 'c1',
      'page': 0,
      'labels': [1, 2],
    });
    await queue.clear();
    await repo(
      (req) async => http.Response('stale', 400),
    ).saveOrder('c1', 0, pb);
    expect(await queue.pendingCount, 0);
  });

  testWidgets('on-device panels: detected once, then served from the mirror', (tester) async {
    final db = MirrorDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    const channel = MethodChannel('app.comic_reader/panels');
    final messenger = tester.binding.defaultBinaryMessenger;
    var detects = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      detects++;
      return Float32List.fromList([320, 160, 640, 320, 1, 1]); // the top half of the 640 input
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final r = BubbleRepository(
      client: ApiClient(baseUrl: 'http://x', deviceId: 't', httpClient: MockClient((_) async => http.Response('', 404))),
      mirror: db,
    );

    await tester.runAsync(() async {
      final first = await r.detectedPanels('c1', 3, () => createTestImage(width: 1280, height: 1280, cache: false));
      expect(first!.panels, [const Rect.fromLTRB(0, 0, 1280, 640)]);
      final again = await r.detectedPanels('c1', 3, () async => fail('cached: no image needed'));
      expect(again!.panels, first.panels);
    });
    expect(detects, 1);
  });
}

class _ThrowingQueue extends SyncQueue {
  _ThrowingQueue(String path) : super(queuePath: path);

  @override
  Future<void> enqueue(Map<String, dynamic> entry) async =>
      throw const FileSystemException('disk full');
}
