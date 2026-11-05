import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:comic_reader_app/providers/providers.dart';
import 'package:comic_reader_app/screens/label_screen.dart';
import 'package:comic_reader_app/services/label_client.dart';
import 'package:comic_reader_app/widgets/label_canvas.dart';

/// Fake label server. Pages have meta w/h only, plus an optional prefill.
class _Server {
  final List<String> queue;
  final List<String> done;
  final Map<String, List<List<double>>> prefill;
  final requests = <http.Request>[];
  bool failOrder = false;
  bool failPut = false;

  _Server({required this.queue, this.done = const [], this.prefill = const {}});

  LabelClient client() => LabelClient(
        baseUrl: 'http://x',
        httpClient: MockClient((req) async {
          requests.add(req);
          final p = req.url.path.replaceFirst('/labeller/', '');
          if (req.method == 'GET' && p == 'pages.json') {
            return http.Response(jsonEncode(queue), 200);
          }
          if (req.method == 'GET' && p == 'done.json') {
            return http.Response(jsonEncode(done), 200);
          }
          if (req.method == 'GET' && p.startsWith('meta/')) {
            return http.Response(jsonEncode({'w': 100, 'h': 150}), 200);
          }
          if (req.method == 'GET' && p.startsWith('prefill/')) {
            final id = p.substring(8).replaceAll('.json', '');
            final boxes = prefill[id];
            if (boxes == null) return http.Response('', 404);
            return http.Response(
              jsonEncode({
                'w': 100,
                'h': 150,
                'boxes': [
                  for (final b in boxes) {'b': b, 'conf': 0.9},
                ],
              }),
              200,
            );
          }
          if (req.method == 'POST' && p == 'order') {
            if (failOrder) return http.Response('{"error":"boom"}', 500);
            final n = (jsonDecode(req.body)['boxes'] as List).length;
            return http.Response(
              jsonEncode({'order': List.generate(n, (i) => i)}),
              200,
            );
          }
          if (req.method == 'PUT' && failPut) return http.Response('', 500);
          if (req.method == 'PUT') return http.Response('{}', 200);
          return http.Response('', 404);
        }),
      );

  List<http.Request> get puts =>
      requests.where((r) => r.method == 'PUT').toList();
}

/// No disk cache in widget tests (path_provider has no plugin here): every
/// page image just fails, which the canvas shows as a blank page.
class _NoImages extends Fake implements BaseCacheManager {
  @override
  Stream<FileResponse> getFileStream(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool withProgress = false,
  }) => Stream.error(Exception('no images in tests'));
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _pump(WidgetTester tester, _Server server, Widget home) async {
  tester.view.physicalSize = const Size(1180, 820);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [labelClientProvider.overrideWithValue(server.client())],
      child: MaterialApp(home: home),
    ),
  );
  await _settle(tester);
}

void main() {
  setUpAll(() => CachedNetworkImageProvider.defaultCacheManager = _NoImages());

  testWidgets('opens on first unlabelled page and shows progress', (
    tester,
  ) async {
    final server = _Server(queue: ['a', 'b', 'c'], done: ['a', 'b']);
    await _pump(tester, server, const LabelScreen());

    expect(find.text('2 / 3'), findsOneWidget);
    expect(find.text('#c'), findsOneWidget);
  });

  testWidgets('Order then Save PUTs to labels/<id>.json and advances', (
    tester,
  ) async {
    final server = _Server(
      queue: ['a', 'b', 'c'],
      done: ['a'],
      prefill: {
        'b': [
          [0.1, 0.1, 0.5, 0.5],
        ],
      },
    );
    await _pump(tester, server, const LabelScreen());
    expect(find.text('#b'), findsOneWidget);

    await tester.tap(find.text('Order ▸'));
    await _settle(tester);
    expect(
      server.requests.where((r) => r.url.path == '/labeller/order'),
      hasLength(1),
    );

    await tester.tap(find.text('Save ▸'));
    await _settle(tester);

    final put = server.puts.single;
    expect(put.url.path, '/labeller/labels/b.json');
    final body = jsonDecode(put.body);
    expect(body['boxes'], [
      [0.1, 0.1, 0.5, 0.5],
    ]);
    expect(body['order'], [0]);
    expect(find.text('#c'), findsOneWidget);
  });

  testWidgets('No panels saves empty body', (tester) async {
    final server = _Server(
      queue: ['a', 'b'],
      prefill: {
        'a': [
          [0.1, 0.1, 0.5, 0.5],
        ],
      },
    );
    await _pump(tester, server, const LabelScreen());

    await tester.tap(find.text('No panels'));
    await _settle(tester);

    final put = server.puts.single;
    expect(put.url.path, '/labeller/labels/a.json');
    final body = jsonDecode(put.body);
    expect(body['boxes'], isEmpty);
    expect(body['order'], isEmpty);
  });

  testWidgets('drag on empty draws a box', (tester) async {
    final server = _Server(queue: ['a']);
    await _pump(tester, server, const LabelScreen());
    expect(find.text('0 boxes'), findsOneWidget);

    await tester.dragFrom(
      tester.getCenter(find.byType(LabelCanvas)),
      const Offset(120, 120),
    );
    await tester.pump();

    expect(find.text('1 box'), findsOneWidget);
  });

  testWidgets('Boxes step numbers the boxes on its own, so Order ▸ needs no request', (
    tester,
  ) async {
    final server = _Server(
      queue: ['a'],
      prefill: {
        'a': [
          [0.1, 0.1, 0.5, 0.5],
          [0.5, 0.5, 0.9, 0.9],
        ],
      },
    );
    await _pump(tester, server, const LabelScreen());
    final orders = server.requests.where((r) => r.url.path == '/labeller/order');
    expect(orders, isEmpty);

    await tester.pump(const Duration(milliseconds: 450));
    await _settle(tester);
    expect(orders, hasLength(1));
    expect(tester.widget<LabelCanvas>(find.byType(LabelCanvas)).editor.orderFresh, isTrue);

    await tester.tap(find.text('Order ▸'));
    await _settle(tester);
    expect(orders, hasLength(1));
    expect(find.text('Save ▸'), findsOneWidget);
  });

  testWidgets('Skip moves to the next unlabelled page without saving', (
    tester,
  ) async {
    final server = _Server(queue: ['a', 'b', 'c'], done: ['b']);
    await _pump(tester, server, const LabelScreen());
    expect(find.text('#a'), findsOneWidget);

    await tester.tap(find.text('Skip ▸'));
    await _settle(tester);

    expect(find.text('#c'), findsOneWidget);
    expect(server.puts, isEmpty);
  });

  testWidgets('Delete removes the selected box, and is off with none selected', (
    tester,
  ) async {
    final server = _Server(
      queue: ['a'],
      prefill: {
        'a': [
          [0.2, 0.2, 0.8, 0.8],
        ],
      },
    );
    await _pump(tester, server, const LabelScreen());
    expect(find.text('1 box'), findsOneWidget);

    await tester.tap(find.text('Delete'));
    await tester.pump();
    expect(find.text('1 box'), findsOneWidget);

    await tester.tapAt(tester.getCenter(find.byType(LabelCanvas)));
    await tester.pump();
    await tester.tap(find.text('Delete'));
    await tester.pump();
    expect(find.text('0 boxes'), findsOneWidget);
  });

  testWidgets('two-finger tap undoes', (tester) async {
    final server = _Server(queue: ['a']);
    await _pump(tester, server, const LabelScreen());
    final c = tester.getCenter(find.byType(LabelCanvas));
    await tester.dragFrom(c, const Offset(120, 120));
    await tester.pump();
    expect(find.text('1 box'), findsOneWidget);

    final g1 = await tester.startGesture(c - const Offset(40, 0), pointer: 1);
    final g2 = await tester.startGesture(c + const Offset(40, 0), pointer: 2);
    await g1.up();
    await g2.up();
    await tester.pump();

    expect(find.text('0 boxes'), findsOneWidget);
  });

  testWidgets('single-page mode hides the mode switch and pops after save', (
    tester,
  ) async {
    final server = _Server(
      queue: ['a'],
      prefill: {
        'z': [
          [0.1, 0.1, 0.5, 0.5],
        ],
      },
    );
    await _pump(
      tester,
      server,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const LabelScreen(singleId: 'z'),
            ),
          ),
          child: const Text('open'),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await _settle(tester);

    expect(find.byType(LabelScreen), findsOneWidget);
    expect(find.text('#z'), findsOneWidget);
    expect(find.text('Balloons'), findsNothing);

    await tester.tap(find.text('Order ▸'));
    await _settle(tester);
    await tester.tap(find.text('Save ▸'));
    await _settle(tester);
    await tester.pump(const Duration(milliseconds: 400));

    expect(server.puts.single.url.path, '/labeller/labels/z.json');
    expect(find.byType(LabelScreen), findsNothing);
  });

  testWidgets('numbering failure shows the error and stays on Boxes', (
    tester,
  ) async {
    final server = _Server(
      queue: ['a'],
      prefill: {
        'a': [
          [0.1, 0.1, 0.5, 0.5],
        ],
      },
    )..failOrder = true;
    await _pump(tester, server, const LabelScreen());

    await tester.tap(find.text('Order ▸'));
    await _settle(tester);

    expect(find.textContaining("Couldn't number the boxes:"), findsOneWidget);
    expect(find.text('Order ▸'), findsOneWidget);
    expect(find.text('No panels'), findsOneWidget);
  });

  testWidgets('a failed save shows SAVE FAILED in the top bar', (
    tester,
  ) async {
    final server = _Server(queue: ['a', 'b'])..failPut = true;
    await _pump(tester, server, const LabelScreen());

    await tester.tap(find.text('No panels'));
    await _settle(tester);

    expect(find.textContaining('SAVE FAILED for a'), findsOneWidget);
  });

  Future<void> openSingle(WidgetTester tester, _Server server) async {
    await _pump(
      tester,
      server,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const LabelScreen(singleId: 'z'),
            ),
          ),
          child: const Text('open'),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await _settle(tester);
  }

  testWidgets('single-page mode stays on SAVE FAILED when the PUT fails', (
    tester,
  ) async {
    final server = _Server(queue: ['a'])..failPut = true;
    await openSingle(tester, server);

    await tester.tap(find.text('No panels'));
    await _settle(tester);
    await tester.pump(const Duration(milliseconds: 400));

    expect(server.puts.single.url.path, '/labeller/labels/z.json');
    expect(find.byType(LabelScreen), findsOneWidget);
    expect(find.textContaining('SAVE FAILED for z'), findsOneWidget);
  });

  testWidgets('a successful Order retry clears the numbering error', (
    tester,
  ) async {
    final server = _Server(
      queue: ['a'],
      prefill: {
        'a': [
          [0.1, 0.1, 0.5, 0.5],
        ],
      },
    )..failOrder = true;
    await _pump(tester, server, const LabelScreen());
    await tester.tap(find.text('Order ▸'));
    await _settle(tester);
    expect(find.textContaining("Couldn't number"), findsOneWidget);

    server.failOrder = false;
    await tester.tap(find.text('Order ▸'));
    await _settle(tester);

    expect(find.text('Save ▸'), findsOneWidget);
    expect(find.textContaining("Couldn't number"), findsNothing);
  });

  testWidgets('an empty queue says so instead of spinning', (tester) async {
    await _pump(tester, _Server(queue: []), const LabelScreen());

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Nothing in this queue.'), findsWidgets);
  });

  testWidgets('a drag saves the contain-rect fractions of its end points', (
    tester,
  ) async {
    final server = _Server(queue: ['a']); // meta: 100 x 150
    await _pump(tester, server, const LabelScreen());

    // Page is contain-fitted (and centred) in the canvas at 1x.
    final c = tester.getRect(find.byType(LabelCanvas));
    final scale = (c.width / 100) < (c.height / 150)
        ? c.width / 100
        : c.height / 150;
    final page = Rect.fromCenter(
      center: c.center,
      width: 100 * scale,
      height: 150 * scale,
    );
    Offset at(double fx, double fy) =>
        Offset(page.left + fx * page.width, page.top + fy * page.height);

    final g = await tester.startGesture(at(0.2, 0.25));
    await g.moveTo(at(0.4, 0.4));
    await g.moveTo(at(0.7, 0.6));
    await g.up();
    await tester.pump();
    await tester.tap(find.text('Order ▸'));
    await _settle(tester);
    await tester.tap(find.text('Save ▸'));
    await _settle(tester);

    final box = (jsonDecode(server.puts.single.body)['boxes'] as List).single
        as List;
    const want = [0.2, 0.25, 0.7, 0.6];
    for (var k = 0; k < 4; k++) {
      expect((box[k] as num).toDouble(), closeTo(want[k], 0.001));
    }
  });

  testWidgets('sessions are disposed on mode switch and on close', (
    tester,
  ) async {
    final live = <Object>{};
    void track(ObjectEvent e) {
      if (e.object is! LabelSession) return;
      if (e is ObjectCreated) live.add(e.object);
      if (e is ObjectDisposed) live.remove(e.object);
    }

    FlutterMemoryAllocations.instance.addListener(track);
    addTearDown(
        () => FlutterMemoryAllocations.instance.removeListener(track));

    final server = _Server(queue: ['a']);
    await _pump(tester, server, const LabelScreen());
    expect(live, hasLength(1));
    await tester.tap(find.text('Balloons'));
    await _settle(tester);
    expect(live, hasLength(1));

    await tester.pumpWidget(const SizedBox());
    expect(live, isEmpty);
  });
}
