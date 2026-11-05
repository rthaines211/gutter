import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:comic_reader_app/services/api_client.dart';
import 'package:comic_reader_app/services/app_logger.dart';
import 'package:comic_reader_app/services/label_client.dart';
import 'package:comic_reader_app/services/label_editor.dart';

/// Routes for an empty panels page `id`: no prefill, no saved label, w/h
/// from meta. Covers the GETs `_loadCurrent`/`_fetchPage` issue per page.
Map<String, http.Response> _emptyPageRoutes(String id) => {
      'GET /labeller/prefill/$id.json': http.Response('', 404),
      'GET /labeller/labels/$id.json': http.Response('', 404),
      'GET /labeller/meta/$id.json':
          http.Response(jsonEncode({'w': 10, 'h': 20}), 200),
    };

LabelClient _clientWithRoutes(
  Map<String, http.Response> routes, {
  List<http.Request>? log,
}) {
  return LabelClient(
    baseUrl: 'http://x',
    httpClient: MockClient((req) async {
      log?.add(req);
      final key = '${req.method} ${req.url.path}';
      return routes[key] ?? http.Response('', 404);
    }),
  );
}

void main() {
  group('LabelClient', () {
    test('requests go under /labeller/', () async {
      final log = <http.Request>[];
      final client = _clientWithRoutes({
        'GET /labeller/pages.json': http.Response(jsonEncode(['a', 'b']), 200),
      }, log: log);

      final ids = await client.queue(LabelMode.panels);

      expect(ids, ['a', 'b']);
      expect(log.single.url.toString(), 'http://x/labeller/pages.json');
    });

    test(
      'page() prefers saved label, keeps prefill for reset, builds balloon '
      'context from confident panel prefill',
      () async {
        final client = _clientWithRoutes({
          'GET /labeller/bprefill/0001.json': http.Response(
            jsonEncode({
              'w': 100,
              'h': 200,
              'boxes': [
                {'b': [0.1, 0.1, 0.2, 0.2], 'conf': 0.9, 'kind': 'caption'},
              ],
            }),
            200,
          ),
          'GET /labeller/balloons/0001.json': http.Response(
            jsonEncode({
              'id': '0001',
              'w': 100,
              'h': 200,
              'boxes': [
                [0.3, 0.3, 0.4, 0.4],
              ],
              'kinds': ['balloon'],
              'order': [0],
              'note': 'hi',
            }),
            200,
          ),
          'GET /labeller/labels/0001.json': http.Response('', 404),
          'GET /labeller/prefill/0001.json': http.Response(
            jsonEncode({
              'w': 100,
              'h': 200,
              'boxes': [
                {'b': [0.0, 0.0, 0.1, 0.1], 'conf': 0.9},
                {'b': [0.5, 0.5, 0.6, 0.6], 'conf': 0.2},
              ],
            }),
            200,
          ),
        });

        final page = await client.page(LabelMode.balloons, '0001');

        expect(page.id, '0001');
        expect(page.w, 100);
        expect(page.h, 200);
        // Prefill is kept as-is (for "reset to prefill"), unfiltered.
        expect(page.prefill, [[0.1, 0.1, 0.2, 0.2]]);
        expect(page.prefillKinds, ['caption']);
        // Saved label wins over prefill for the live boxes.
        expect(page.saved!.boxes, [[0.3, 0.3, 0.4, 0.4]]);
        expect(page.saved!.kinds, ['balloon']);
        expect(page.saved!.order, [0]);
        expect(page.saved!.note, 'hi');
        // No saved panel label (labels/0001.json 404'd), so context comes
        // from the panel prefill, filtered to conf >= 0.5.
        expect(page.context, [[0.0, 0.0, 0.1, 0.1]]);
      },
    );

    test('importPage 404 throws LabelImportMissing', () async {
      final client = _clientWithRoutes({
        'POST /labeller/import': http.Response('', 404),
      });

      await expectLater(
        () => client.importPage('book.cbz', 3),
        throwsA(isA<LabelImportMissing>()),
      );
    });
  });

  group('LabelSession', () {
    test('session starts at first unlabelled', () async {
      final client = _clientWithRoutes({
        'GET /labeller/pages.json':
            http.Response(jsonEncode(['a', 'b', 'c']), 200),
        'GET /labeller/done.json': http.Response(jsonEncode(['a']), 200),
        'GET /labeller/flags.json': http.Response('', 404),
        'GET /labeller/prefill/b.json': http.Response('', 404),
        'GET /labeller/labels/b.json': http.Response('', 404),
        'GET /labeller/meta/b.json':
            http.Response(jsonEncode({'w': 10, 'h': 20}), 200),
      });
      final session = LabelSession(client: client, mode: LabelMode.panels);

      await session.load();

      expect(session.ids, ['a', 'b', 'c']);
      expect(session.index, 1);
      expect(session.current!.id, 'b');
    });

    test('nextTodo with all done stays and says Every page is labelled.',
        () async {
      final client = _clientWithRoutes({
        'GET /labeller/pages.json': http.Response(jsonEncode(['a', 'b']), 200),
        'GET /labeller/done.json':
            http.Response(jsonEncode(['a', 'b']), 200),
        'GET /labeller/flags.json': http.Response('', 404),
        'GET /labeller/prefill/a.json': http.Response('', 404),
        'GET /labeller/labels/a.json': http.Response('', 404),
        'GET /labeller/meta/a.json':
            http.Response(jsonEncode({'w': 10, 'h': 20}), 200),
      });
      final session = LabelSession(client: client, mode: LabelMode.panels);
      await session.load();
      final indexBefore = session.index;

      await session.nextTodo();

      expect(session.index, indexBefore);
      expect(session.status, 'Every page is labelled.');
    });

    test('save failure un-marks done and reports id', () async {
      final client = _clientWithRoutes({
        'GET /labeller/pages.json': http.Response(jsonEncode(['x']), 200),
        'GET /labeller/done.json': http.Response(jsonEncode([]), 200),
        'GET /labeller/flags.json': http.Response('', 404),
        'GET /labeller/prefill/x.json': http.Response('', 404),
        'GET /labeller/labels/x.json': http.Response('', 404),
        'GET /labeller/meta/x.json':
            http.Response(jsonEncode({'w': 10, 'h': 20}), 200),
        'PUT /labeller/labels/x.json': http.Response('bad gateway', 502),
      });
      final session = LabelSession(client: client, mode: LabelMode.panels);
      await session.load();
      final editor = LabelEditor(
        mode: LabelMode.panels,
        prefillBoxes: [],
        prefillKinds: [],
      )..markNone();

      await session.save(editor);

      expect(session.done.contains('x'), isFalse);
      expect(session.status, contains('SAVE FAILED for x'));
    });

    test('single-page session ignores next/prev', () async {
      final client = _clientWithRoutes({
        'GET /labeller/flags.json': http.Response('', 404),
        'GET /labeller/done.json': http.Response(jsonEncode([]), 200),
        'GET /labeller/prefill/z.json': http.Response('', 404),
        'GET /labeller/labels/z.json': http.Response('', 404),
        'GET /labeller/meta/z.json':
            http.Response(jsonEncode({'w': 10, 'h': 20}), 200),
      });
      final session = LabelSession(
        client: client,
        mode: LabelMode.panels,
        singleId: 'z',
      );
      await session.load();

      expect(session.ids, ['z']);

      await session.next();
      await session.prev();
      await session.nextTodo();

      expect(session.ids, ['z']);
      expect(session.index, 0);
    });
  });

  group('LabelSession fix round 1', () {
    test(
      'overlapping navigations: a slower first fetch does not clobber the '
      'later one',
      () async {
        final gate = Completer<void>();
        final client = LabelClient(
          baseUrl: 'http://x',
          httpClient: MockClient((req) async {
            final path = req.url.path;
            if (path == '/labeller/pages.json') {
              return http.Response(jsonEncode(['a', 'b', 'c']), 200);
            }
            if (path == '/labeller/done.json') {
              return http.Response(jsonEncode([]), 200);
            }
            if (path == '/labeller/flags.json') return http.Response('', 404);
            if (path.contains('/b.json')) {
              await gate.future; // hold b's fetch open until released
            }
            if (path.endsWith('/meta/a.json') ||
                path.endsWith('/meta/b.json') ||
                path.endsWith('/meta/c.json')) {
              return http.Response(jsonEncode({'w': 10, 'h': 20}), 200);
            }
            return http.Response('', 404); // prefill/labels: none saved
          }),
        );
        final session = LabelSession(client: client, mode: LabelMode.panels);
        await session.load(); // current = 'a'

        final firstNav = session.next(); // targets 'b'; hangs on the gate
        await Future<void>.delayed(Duration.zero);
        await session.next(); // targets 'c'; resolves immediately
        expect(session.current!.id, 'c');

        gate.complete(); // release b's stale fetch
        await firstNav;

        expect(session.current!.id, 'c');
      },
    );

    test('navigating to a prefetched page issues no new GETs for it',
        () async {
      final log = <http.Request>[];
      final client = _clientWithRoutes({
        'GET /labeller/pages.json':
            http.Response(jsonEncode(['a', 'b', 'c', 'd']), 200),
        'GET /labeller/done.json': http.Response(jsonEncode([]), 200),
        'GET /labeller/flags.json': http.Response('', 404),
        ..._emptyPageRoutes('a'),
        ..._emptyPageRoutes('b'),
        ..._emptyPageRoutes('c'),
        ..._emptyPageRoutes('d'),
      }, log: log);
      final session = LabelSession(client: client, mode: LabelMode.panels);

      await session.load(); // loads 'a', prefetches b, c, d
      // Prefetch is fire-and-forget; let its unawaited requests land.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      final countBefore =
          log.where((r) => r.url.path.contains('/b.json')).length;
      expect(countBefore, greaterThan(0));

      await session.next(); // navigates to the already-prefetched 'b'

      final countAfter =
          log.where((r) => r.url.path.contains('/b.json')).length;
      expect(countAfter, countBefore);
      expect(session.current!.id, 'b');
    });

    test('save succeeds even when the nextTodo navigation throws', () async {
      final client = _clientWithRoutes({
        'GET /labeller/pages.json': http.Response(jsonEncode(['x', 'y']), 200),
        'GET /labeller/done.json': http.Response(jsonEncode([]), 200),
        'GET /labeller/flags.json': http.Response('', 404),
        ..._emptyPageRoutes('x'),
        'PUT /labeller/labels/x.json':
            http.Response(jsonEncode({'saved': 0}), 200),
        // y's own page load blows up; nextTodo() (called from save) should
        // not be allowed to take x's save outcome down with it.
        'GET /labeller/prefill/y.json':
            http.Response('server error', 500),
      });
      final session = LabelSession(client: client, mode: LabelMode.panels);
      await session.load();
      final editor = LabelEditor(
        mode: LabelMode.panels,
        prefillBoxes: [],
        prefillKinds: [],
      )..markNone();

      await session.save(editor);

      expect(session.done.contains('x'), isTrue);
      expect(session.status, contains('Saved x'));
    });

    test(
      'failed-save status is sticky until that id is re-saved '
      'successfully',
      () async {
        var failA = true;
        final client = LabelClient(
          baseUrl: 'http://x',
          httpClient: MockClient((req) async {
            final path = req.url.path;
            if (req.method == 'PUT' && path == '/labeller/labels/a.json') {
              if (failA) return http.Response('bad gateway', 502);
              return http.Response(jsonEncode({'saved': 0}), 200);
            }
            if (req.method == 'PUT' && path == '/labeller/labels/b.json') {
              return http.Response(jsonEncode({'saved': 0}), 200);
            }
            if (path == '/labeller/pages.json') {
              return http.Response(jsonEncode(['a', 'b']), 200);
            }
            if (path == '/labeller/done.json') {
              return http.Response(jsonEncode([]), 200);
            }
            if (path == '/labeller/flags.json') return http.Response('', 404);
            if (path.endsWith('/meta/a.json') ||
                path.endsWith('/meta/b.json')) {
              return http.Response(jsonEncode({'w': 10, 'h': 20}), 200);
            }
            return http.Response('', 404); // prefill/labels: none saved
          }),
        );
        final session = LabelSession(client: client, mode: LabelMode.panels);
        await session.load(); // current = 'a'

        final editorA = LabelEditor(
          mode: LabelMode.panels,
          prefillBoxes: [],
          prefillKinds: [],
        )..markNone();
        await session.save(editorA); // fails; nextTodo moves on to 'b'
        expect(session.current!.id, 'b');
        expect(session.status, contains('SAVE FAILED for a'));

        final editorB = LabelEditor(
          mode: LabelMode.panels,
          prefillBoxes: [],
          prefillKinds: [],
        )..markNone();
        await session.save(editorB); // succeeds
        expect(session.done.contains('b'), isTrue);
        // Still sticky for 'a', even after a different page saved fine.
        expect(session.status, contains('SAVE FAILED for a'));

        await session.prev(); // back to 'a'
        failA = false;
        final editorA2 = LabelEditor(
          mode: LabelMode.panels,
          prefillBoxes: [],
          prefillKinds: [],
        )..markNone();
        await session.save(editorA2); // now succeeds

        expect(session.done.contains('a'), isTrue);
        expect(session.status, isNot(contains('SAVE FAILED')));
      },
    );
  });

  group('LabelSession final review', () {
    LabelEditor none() => LabelEditor(
          mode: LabelMode.panels,
          prefillBoxes: [],
          prefillKinds: [],
        )..markNone();

    test('a second Save while the next page is loading still writes the '
        'page on screen, never the next one', () async {
      final gate = Completer<void>();
      final puts = <String>[];
      final client = LabelClient(
        baseUrl: 'http://x',
        httpClient: MockClient((req) async {
          final path = req.url.path;
          if (req.method == 'PUT') {
            puts.add(path);
            return http.Response('{}', 200);
          }
          if (path == '/labeller/pages.json') {
            return http.Response(jsonEncode(['a', 'b']), 200);
          }
          if (path == '/labeller/done.json') {
            return http.Response(jsonEncode([]), 200);
          }
          if (path.contains('/b.json')) await gate.future;
          if (path.startsWith('/labeller/meta/')) {
            return http.Response(jsonEncode({'w': 10, 'h': 20}), 200);
          }
          return http.Response('', 404);
        }),
      );
      final session = LabelSession(client: client, mode: LabelMode.panels);
      await session.load(); // current = 'a'; b's prefetch hangs on the gate

      final first = session.save(none()); // nextTodo -> b, pending
      await Future<void>.delayed(Duration.zero);
      expect(session.current!.id, 'a');
      final second = session.save(none()); // double tap
      await Future<void>.delayed(Duration.zero);

      gate.complete();
      await Future.wait([first, second]);

      expect(puts, isNotEmpty);
      expect(puts, everyElement('/labeller/labels/a.json'));
      expect(session.done.contains('b'), isFalse);
    });

    test('a failed next() leaves the index on the page still shown',
        () async {
      final client = _clientWithRoutes({
        'GET /labeller/pages.json': http.Response(jsonEncode(['a', 'b']), 200),
        'GET /labeller/done.json': http.Response(jsonEncode([]), 200),
        'GET /labeller/flags.json': http.Response('', 404),
        ..._emptyPageRoutes('a'),
        'GET /labeller/prefill/b.json': http.Response('boom', 500),
      });
      final session = LabelSession(client: client, mode: LabelMode.panels);
      await session.load();

      await expectLater(session.next(), throwsA(isA<ApiException>()));

      expect(session.index, 0);
      expect(session.current!.id, 'a');
    });

    test('load with every page labelled says so', () async {
      final client = _clientWithRoutes({
        'GET /labeller/pages.json': http.Response(jsonEncode(['a', 'b']), 200),
        'GET /labeller/done.json': http.Response(jsonEncode(['a', 'b']), 200),
        'GET /labeller/flags.json': http.Response('', 404),
        ..._emptyPageRoutes('a'),
        ..._emptyPageRoutes('b'),
      });
      final session = LabelSession(client: client, mode: LabelMode.panels);

      await session.load();

      expect(session.current!.id, 'a');
      expect(session.status, 'Every page is labelled.');
    });

    test('a save landing after dispose does not throw', () async {
      final gate = Completer<void>();
      final client = LabelClient(
        baseUrl: 'http://x',
        httpClient: MockClient((req) async {
          if (req.method == 'PUT') {
            await gate.future;
            return http.Response('{}', 200);
          }
          if (req.url.path.startsWith('/labeller/meta/')) {
            return http.Response(jsonEncode({'w': 10, 'h': 20}), 200);
          }
          if (req.url.path == '/labeller/done.json') {
            return http.Response(jsonEncode([]), 200);
          }
          return http.Response('', 404);
        }),
      );
      final session = LabelSession(
        client: client,
        mode: LabelMode.panels,
        singleId: 'z',
      );
      await session.load();
      final saving = session.save(none());
      session.dispose();
      gate.complete();
      await saving; // notifyListeners on a disposed notifier would throw
    });
  });

  group('fixPageId', () {
    setUp(() async => AppLogger.init(logDirFactory: () async => null));
    tearDown(() => AppLogger.resetForTest());

    test('flags with the mode\'s reason then imports the decoded path',
        () async {
      const book = 'Batman by Paul Dini (2006)/Batman v01 001.cbz';
      final comicId = base64Url.encode(utf8.encode(book));
      final log = <http.Request>[];

      final api = ApiClient(
        baseUrl: 'http://x',
        deviceId: 'dev',
        httpClient: MockClient((req) async {
          log.add(req);
          return http.Response('{}', 200);
        }),
      );
      final labels = LabelClient(
        baseUrl: 'http://x',
        httpClient: MockClient((req) async {
          log.add(req);
          return http.Response(jsonEncode({'id': '0007'}), 200);
        }),
      );

      final id = await fixPageId(
        api: api,
        labels: labels,
        comicId: comicId,
        page: 4,
        mode: LabelMode.balloons,
      );

      expect(id, '0007');
      expect(log, hasLength(2));
      expect(log[0].method, 'PUT');
      expect(log[0].url.path, '/comics/$comicId/pages/4/flag');
      expect(
        jsonDecode(log[0].body),
        {'reason': 'balloon_cut', 'zoom': 'bubbles'},
      );
      expect(log[1].method, 'POST');
      expect(log[1].url.path, '/labeller/import');
      expect(jsonDecode(log[1].body), {'book': book, 'page': 4});
    });

    test('a flag failure is reported as LabelFlagFailed, not an import '
        'failure', () async {
      final api = ApiClient(
        baseUrl: 'http://x',
        deviceId: 'dev',
        httpClient: MockClient((_) async => http.Response('{}', 502)),
      );
      final labels = LabelClient(
        baseUrl: 'http://x',
        httpClient: MockClient(
            (_) async => http.Response(jsonEncode({'id': '0007'}), 200)),
      );

      await expectLater(
        fixPageId(
          api: api,
          labels: labels,
          comicId: base64Url.encode(utf8.encode('b.cbz')),
          page: 0,
          mode: LabelMode.panels,
        ),
        throwsA(isA<LabelFlagFailed>()),
      );
    });
  });
}
