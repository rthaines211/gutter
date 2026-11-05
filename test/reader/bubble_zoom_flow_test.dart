import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:comic_reader_app/providers/settings_provider.dart';
import 'package:comic_reader_app/screens/reader_screen.dart';
import 'package:comic_reader_app/widgets/bubble_pop_overlay.dart';
import 'package:comic_reader_app/widgets/volume_key_listener.dart';

import 'fake_comic_server.dart';
import 'harness.dart';

Map<String, dynamic> sidecar(int n) => {
  'v': 1,
  'w': 1000,
  'h': 1500,
  'bubbles': [
    for (var i = 0; i < n; i++)
      {
        'r': [100, 100 + i * 300, 300, 150],
        'label': i + 1,
      },
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory env;
  late FakeComicServer server;

  setUpAll(() async => env = await initReaderTestEnv());
  useComicServer(
    () => FakeComicServer()..comics['c1'] = List.filled(10, portraitPage),
    (s) => server = s,
    () => server,
  );

  // Same timing as page_reader_flow_test: 250 ms double-tap window, 300 ms page slide.
  Future<void> tapRight(WidgetTester tester) async {
    await tester.tapAt(const Offset(700, 300));
    await tester.pump(const Duration(milliseconds: 260));
    await tester.pump(const Duration(milliseconds: 350));
  }

  Future<void> tapLeft(WidgetTester tester) async {
    await tester.tapAt(const Offset(40, 300));
    await tester.pump(const Duration(milliseconds: 260));
    await tester.pump(const Duration(milliseconds: 350));
  }

  Future<void> longPress(WidgetTester tester) async {
    final g = await tester.startGesture(const Offset(700, 300));
    await tester.pump(const Duration(milliseconds: 600));
    await g.up();
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// Under a loaded machine (the full suite runs files in parallel) a fixed
  /// number of settle rounds isn't always enough: wait for the condition itself.
  Future<void> settleUntil(
    WidgetTester tester,
    bool Function() done, {
    int maxRounds = 300,
  }) async {
    for (var i = 0; i < maxRounds && !done(); i++) {
      await settleImages(tester, rounds: 1);
    }
  }

  /// The page on screen has loaded its image and computed its steps (the
  /// reader keeps a page at opacity 0 until then).
  bool pageReady(WidgetTester tester) => tester
      .widgetList<Opacity>(
        find.ancestor(of: find.byType(Image), matching: find.byType(Opacity)),
      )
      .any((o) => o.opacity == 1);

  /// Wait until [page]'s image is in and its balloons have been asked for, then
  /// let the reply land.
  Future<void> waitForBubbles(
    WidgetTester tester, {
    String comic = 'c1',
    int page = 0,
  }) async {
    await settleUntil(tester, () => pageReady(tester));
    await settleUntil(
      tester,
      () => server.requests.any(
        (r) => r.path == '/comics/$comic/pages/$page/bubbles',
      ),
    );
    await settleImages(tester, rounds: 10);
  }

  int? shown(WidgetTester tester) {
    final f = find.byType(BubblePopOverlay);
    return f.evaluate().isEmpty
        ? null
        : tester.widget<BubblePopOverlay>(f).label;
  }

  List<dynamic> orderPuts() => [
    for (final r in server.requests)
      if (r.method == 'PUT' && r.path.endsWith('/bubbles/order'))
        r.jsonBody!['labels'],
  ];

  testWidgets(
    'taps step balloons, turn the page, and back lands on the last balloon',
    (tester) async {
      server.settings = {'bubble_zoom': true, 'page_fit': 'fitHeight'};
      server.bubbles['c1'] = {0: sidecar(2)};
      final h = await pumpReader(tester, server: server, tempDir: env);
      await settleImages(tester);
      await waitForBubbles(tester);
      expect(shown(tester), isNull, reason: 'step 0 is the whole page');

      await tapRight(tester);
      expect(shown(tester), 1);
      await tapRight(tester);
      expect(shown(tester), 2);
      expect(h.stateOf(tester).currentPage, 0);

      await tapRight(tester);
      await settleImages(tester, rounds: 5);
      expect(h.stateOf(tester).currentPage, 1);
      expect(shown(tester), isNull);

      await tapLeft(tester);
      await settleImages(tester, rounds: 5);
      expect(h.stateOf(tester).currentPage, 0);
      expect(shown(tester), 2);
      await disposeReader(tester);
    },
  );

  testWidgets('volume keys step balloons exactly like tap zones', (
    tester,
  ) async {
    server.settings = {'bubble_zoom': true, 'page_fit': 'fitHeight'};
    server.bubbles['c1'] = {0: sidecar(2)};
    final h = await pumpReader(tester, server: server, tempDir: env);
    await settleImages(tester);
    await waitForBubbles(tester);
    VolumeKeyListener keys() =>
        tester.widget<VolumeKeyListener>(find.byType(VolumeKeyListener));

    keys().onVolumeUp();
    await tester.pump();
    expect(shown(tester), 1);
    keys().onVolumeUp();
    await tester.pump();
    expect(shown(tester), 2);
    keys().onVolumeDown();
    await tester.pump();
    expect(shown(tester), 1);
    keys().onVolumeDown();
    await tester.pump();
    expect(shown(tester), isNull);
    keys().onVolumeUp();
    keys().onVolumeUp();
    keys().onVolumeUp();
    await tester.pump(const Duration(milliseconds: 350));
    await settleImages(tester, rounds: 5);
    expect(h.stateOf(tester).currentPage, 1);
    await disposeReader(tester);
  });

  for (final (name, settings, sc) in [
    ('no sidecar', {'bubble_zoom': true, 'page_fit': 'fitHeight'}, null),
    (
      'zero balloons',
      {'bubble_zoom': true, 'page_fit': 'fitHeight'},
      sidecar(0),
    ),
    (
      'zoom lock on',
      {'bubble_zoom': true, 'zoom_lock': true, 'page_fit': 'fitHeight'},
      sidecar(2),
    ),
    ('setting off', {'page_fit': 'fitHeight'}, sidecar(2)),
  ]) {
    testWidgets('falls back to today\'s behaviour: $name', (tester) async {
      server.settings = settings;
      if (sc != null) server.bubbles['c1'] = {0: sc};
      final h = await pumpReader(tester, server: server, tempDir: env);
      await settleImages(tester);
      await tapRight(tester);
      await settleImages(tester, rounds: 5);
      expect(shown(tester), isNull);
      expect(
        h.stateOf(tester).currentPage,
        1,
        reason: 'fitHeight is one step, so a tap turns the page',
      );
      await disposeReader(tester);
    });
  }

  testWidgets('long-press: not yet, then undo; ignored on the whole page', (
    tester,
  ) async {
    server.settings = {'bubble_zoom': true, 'page_fit': 'fitHeight'};
    server.bubbles['c1'] = {0: sidecar(3)};
    await pumpReader(tester, server: server, tempDir: env);
    await settleImages(tester);
    await waitForBubbles(tester);

    await longPress(tester); // step 0
    await settleImages(tester, rounds: 3);
    expect(orderPuts(), isEmpty);

    await tapRight(tester);
    expect(shown(tester), 1);
    await longPress(tester);
    await settleImages(tester, rounds: 3);
    expect(shown(tester), 2);
    await longPress(tester);
    await settleImages(tester, rounds: 3);
    expect(shown(tester), 1);
    expect(orderPuts(), [
      [2, 1, 3],
      [1, 2, 3],
    ]);
    await disposeReader(tester);
  });

  testWidgets('the first balloon step tells you about long-press, once', (
    tester,
  ) async {
    server.settings = {'bubble_zoom': true, 'page_fit': 'fitHeight'};
    server.bubbles['c1'] = {0: sidecar(2)};
    await pumpReader(tester, server: server, tempDir: env);
    await settleImages(tester);
    await waitForBubbles(tester);
    final hint = find.textContaining('Long-press');
    expect(hint, findsNothing, reason: 'not on the whole page');

    await tapRight(tester);
    expect(shown(tester), 1);
    await tester.pump();
    expect(hint, findsOneWidget);

    // The snack bar's timer starts once it has slid in; then it times out.
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(hint, findsNothing);
    await tapLeft(tester);
    await tapRight(tester);
    await tester.pump();
    expect(shown(tester), 1);
    expect(hint, findsNothing, reason: 'shown once, ever');
    await disposeReader(tester);
  });

  testWidgets('turning the setting off mid-page leaves no invisible steps', (
    tester,
  ) async {
    server.settings = {'bubble_zoom': true, 'page_fit': 'fitHeight'};
    server.bubbles['c1'] = {0: sidecar(3)};
    final h = await pumpReader(tester, server: server, tempDir: env);
    await settleImages(tester);
    await waitForBubbles(tester);
    await tapRight(tester);
    expect(shown(tester), 1);

    final container = h.containerOf(tester);
    final current = container.read(settingsProvider).value!;
    // Not awaited: save() PUTs /settings, which only completes inside settleImages' runAsync.
    container
        .read(settingsProvider.notifier)
        .save(current.copyWith(zoomMode: 'off'));
    await settleImages(tester, rounds: 5);
    expect(shown(tester), isNull);
    await tapRight(tester);
    await settleImages(tester, rounds: 5);
    expect(h.stateOf(tester).currentPage, 1);
    await disposeReader(tester);
  });

  // Review fixes ---------------------------------------------------------------

  testWidgets(
    'a second reader opened with settings already loaded gets balloons on its first page',
    (tester) async {
      server.settings = {'bubble_zoom': true, 'page_fit': 'fitHeight'};
      server.comics['c2'] = List.filled(6, portraitPage);
      server.bubbles['c2'] = {3: sidecar(2)};
      await pumpReader(tester, server: server, tempDir: env);
      await settleImages(tester);

      final nav = Navigator.of(tester.element(find.byType(ReaderScreen)));
      nav.push(
        MaterialPageRoute(
          builder: (_) => const ReaderScreen(
            comicId: 'c2',
            comicPath: '/library/c2.cbz',
            initialPage: 3,
          ),
        ),
      );
      await settleImages(tester, rounds: 30);
      await waitForBubbles(tester, comic: 'c2', page: 3);
      await tapRight(tester);
      expect(shown(tester), 1);
      nav.pop();
      await settleImages(tester, rounds: 10);
      await disposeReader(tester);
    },
  );

  // Double-tap's zoom animation doesn't tick in fake-async (see spread_zoom_test);
  // what broke was the synchronous step collapse, so that is what this checks.
  testWidgets('double-tap does not throw away the balloon steps', (
    tester,
  ) async {
    server.settings = {'bubble_zoom': true, 'page_fit': 'fitHeight'};
    server.bubbles['c1'] = {0: sidecar(2)};
    final h = await pumpReader(tester, server: server, tempDir: env);
    await settleImages(tester);
    await waitForBubbles(tester);
    await tester.tapAt(const Offset(400, 300));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(const Offset(400, 300));
    await tester.pump(const Duration(milliseconds: 400));
    await tapRight(tester);
    expect(shown(tester), 1);
    expect(h.stateOf(tester).currentPage, 0);
    await disposeReader(tester);
  });

  testWidgets(
    'toggling Lock Zoom while zoomed leaves the zoom alone when bubble zoom is off',
    (tester) async {
      server.settings = {'page_fit': 'fitHeight'};
      final h = await pumpReader(tester, server: server, tempDir: env);
      await settleImages(tester, rounds: 40);
      await settleUntil(tester, () => pageReady(tester));
      double scale() => tester
          .widget<InteractiveViewer>(find.byType(InteractiveViewer).first)
          .transformationController!
          .value
          .getMaxScaleOnAxis();
      final center = tester.getCenter(find.byType(InteractiveViewer).first);
      final g1 = await tester.startGesture(center - const Offset(30, 0));
      final g2 = await tester.startGesture(center + const Offset(30, 0));
      await g1.moveBy(const Offset(-90, 0));
      await g2.moveBy(const Offset(90, 0));
      await g1.up();
      await g2.up();
      await tester.pump(const Duration(milliseconds: 200));
      expect(scale(), greaterThan(1.2));

      final container = h.containerOf(tester);
      final current = container.read(settingsProvider).value!;
      container
          .read(settingsProvider.notifier)
          .save(current.copyWith(zoomLock: true));
      await settleImages(tester, rounds: 3);
      expect(scale(), greaterThan(1.2));
      await disposeReader(tester);
    },
  );

  testWidgets(
    'a two-page spread on a portrait screen keeps today\'s spread pan',
    (tester) async {
      tester.view.physicalSize = const Size(600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      server.settings = {'bubble_zoom': true};
      server.comics['c1'] = List.filled(4, landscapeSpread);
      server.bubbles['c1'] = {
        0: {...sidecar(2), 'w': 2400},
      };
      await pumpReader(tester, server: server, tempDir: env);
      await settleImages(tester);
      await tester.tapAt(const Offset(560, 500));
      await tester.pump(const Duration(milliseconds: 260));
      await tester.pump(const Duration(milliseconds: 350));
      expect(shown(tester), isNull);
      await disposeReader(tester);
    },
  );

  testWidgets('late sidecar: takes over a page still on its first step', (
    tester,
  ) async {
    server.settings = {'bubble_zoom': true, 'page_fit': 'fitHeight'};
    server.bubbles['c1'] = {0: sidecar(2)};
    server.bubblesDelay = const Duration(milliseconds: 800);
    await pumpReader(tester, server: server, tempDir: env);
    await settleImages(tester, rounds: 40);
    await tapRight(tester);
    expect(shown(tester), 1);
    await disposeReader(tester);
  });

  testWidgets('late sidecar: a page already chunk-panning stays in chunk pan', (
    tester,
  ) async {
    server.settings = {
      'bubble_zoom': true,
    }; // fitScreen on 800x600: several chunk steps
    server.bubbles['c1'] = {0: sidecar(2)};
    server.bubblesDelay = const Duration(seconds: 4);
    final h = await pumpReader(tester, server: server, tempDir: env);
    await settleUntil(
      tester,
      () => pageReady(tester),
    ); // image in, sidecar not yet
    await tapRight(tester); // chunk step 1
    expect(
      h.stateOf(tester).currentPage,
      0,
      reason: 'fitScreen gives several steps',
    );
    await settleImages(tester, rounds: 120); // sidecar lands
    await tapRight(tester);
    expect(shown(tester), isNull);
    await disposeReader(tester);
  });

  testWidgets(
    'a sidecar with a broken mask still pops out (rounded rect), no error',
    (tester) async {
      server.settings = {'bubble_zoom': true, 'page_fit': 'fitHeight'};
      server.bubbles['c1'] = {
        0: {...sidecar(2), 'mask': 'AAAA'},
      };
      await pumpReader(tester, server: server, tempDir: env);
      await settleImages(tester);
      await waitForBubbles(tester);
      await tapRight(tester);
      expect(shown(tester), 1);
      expect(tester.takeException(), isNull);
      await disposeReader(tester);
    },
  );

  testWidgets('balloon cut-outs are built from the full-resolution page', (
    tester,
  ) async {
    // Label PNG at half resolution (500 px for the 1000 px page), label 1 under balloon 1.
    final lab = img.Image(width: 500, height: 750, numChannels: 1);
    for (var y = 55; y < 120; y++) {
      for (var x = 55; x < 195; x++) {
        lab.setPixelR(x, y, 1);
      }
    }
    server.settings = {'bubble_zoom': true, 'page_fit': 'fitHeight'};
    server.bubbles['c1'] = {
      0: {...sidecar(1), 'mask': base64Encode(img.encodePng(lab))},
    };
    await pumpReader(tester, server: server, tempDir: env);
    await settleImages(tester, rounds: 40);
    await waitForBubbles(tester);
    await tapRight(tester);
    await settleUntil(tester, () {
      final f = find.byType(BubblePopOverlay);
      return f.evaluate().isNotEmpty &&
          tester.widget<BubblePopOverlay>(f).parts.first.mask != null;
    });
    final overlay = tester.widget<BubblePopOverlay>(
      find.byType(BubblePopOverlay),
    );
    final part = overlay.parts.single;
    expect(part.mask, isNotNull);
    expect(
      part.mask!.width,
      part.src.width.round(),
      reason: 'page resolution, not the half-size label',
    );
    await disposeReader(tester);
  });

  testWidgets(
    'a balloon whose tail-out pop-out runs off screen slides the page, never scales it',
    (tester) async {
      // A white balloon near the top of a dark page, tail down-left: growing out
      // of the tail it would leave the top of the screen.
      final page = img.Image(width: 1000, height: 1500);
      img.fill(page, color: img.ColorRgb8(120, 40, 40));
      for (var y = 0; y < 300; y++) {
        for (var x = 300; x < 700; x++) {
          final dx = (x - 500) / 150, dy = (y - 110) / 70;
          if (dx * dx + dy * dy <= 1) page.setPixelRgb(x, y, 255, 255, 255);
        }
      }
      img.drawLine(
        page,
        x1: 420,
        y1: 160,
        x2: 340,
        y2: 270,
        color: img.ColorRgb8(255, 255, 255),
        thickness: 26,
      );
      final lab = img.Image(width: 500, height: 750, numChannels: 1);
      for (var y = 0; y < 100; y++) {
        for (var x = 150; x < 350; x++) {
          final dx = (x - 250) / 65, dy = (y - 55) / 28;
          if (dx * dx + dy * dy <= 1) lab.setPixelR(x, y, 1);
        }
      }
      server.comics['c1'] = [
        PageSpec(1000, 1500, page),
        ...List.filled(9, portraitPage),
      ];
      server.settings = {'bubble_zoom': true, 'page_fit': 'fitHeight'};
      server.bubbles['c1'] = {
        0: {
          'v': 1,
          'w': 1000,
          'h': 1500,
          'bubbles': [
            {
              'r': [320, 30, 340, 250],
              'label': 1,
            },
          ],
          'mask': base64Encode(img.encodePng(lab)),
        },
      };
      await pumpReader(tester, server: server, tempDir: env);
      await settleImages(tester, rounds: 40);
      await waitForBubbles(tester);
      Matrix4 transform() => tester
          .widget<InteractiveViewer>(find.byType(InteractiveViewer).first)
          .transformationController!
          .value;
      // Let the cut-out (and its tail) land before stepping: a page not yet
      // started is re-stepped when it does.
      await settleImages(tester, rounds: 40);
      await tapRight(tester);
      await settleUntil(tester, () {
        final f = find.byType(BubblePopOverlay);
        return f.evaluate().isNotEmpty &&
            tester.widget<BubblePopOverlay>(f).tail != null;
      });
      await tester.pump(const Duration(milliseconds: 400));
      final overlay = tester.widget<BubblePopOverlay>(
        find.byType(BubblePopOverlay),
      );
      expect(overlay.tail, isNotNull, reason: 'the tail was found');
      final m = transform();
      expect(m.getMaxScaleOnAxis(), closeTo(1, 0.001));
      expect(
        m.getTranslation().y,
        greaterThan(0),
        reason: 'slid down to make room above',
      );
      await tapLeft(tester);
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        transform().getTranslation().y,
        closeTo(0, 0.01),
        reason: 'whole page is home again',
      );
      await disposeReader(tester);
    },
  );

  testWidgets('fit width on a sideways screen: balloon steps keep the fit-width scale and scroll; a pinch hides the pop-out', (
    tester,
  ) async {
    // 800 x 600 test screen: a 1000 x 1500 page fits 400 wide, so fit width is 2x.
    server.settings = {'bubble_zoom': true, 'page_fit': 'fitWidth'};
    server.bubbles['c1'] = {0: sidecar(3)}; // balloons at page y 100, 400, 700
    await pumpReader(tester, server: server, tempDir: env);
    await settleImages(tester);
    await waitForBubbles(tester);
    Matrix4 transform() => tester
        .widget<InteractiveViewer>(find.byType(InteractiveViewer).first)
        .transformationController!
        .value;
    expect(transform().entry(0, 0), closeTo(2, 0.001), reason: 'step 0: the top of the page at fit width');
    expect(transform().getTranslation().y, closeTo(0, 0.01));

    await tapRight(tester);
    await tester.pump(const Duration(milliseconds: 400));
    expect(shown(tester), 1);
    expect(transform().entry(0, 0), closeTo(2, 0.001));
    await tapRight(tester);
    await tester.pump(const Duration(milliseconds: 400));
    await tapRight(tester);
    await tester.pump(const Duration(milliseconds: 400));
    expect(shown(tester), 3);
    expect(transform().entry(0, 0), closeTo(2, 0.001));
    expect(transform().getTranslation().y, lessThan(0), reason: 'scrolled down to the third balloon');

    // Pinch in: off the step, so no pop-out.
    final center = tester.getCenter(find.byType(InteractiveViewer).first);
    final g1 = await tester.startGesture(center - const Offset(30, 0));
    final g2 = await tester.startGesture(center + const Offset(30, 0));
    await g1.moveBy(const Offset(-90, 0));
    await g2.moveBy(const Offset(90, 0));
    await tester.pump();
    expect(shown(tester), isNull);
    await g1.up();
    await g2.up();
    await tester.pump(const Duration(milliseconds: 200));
    expect(shown(tester), isNull);
    await disposeReader(tester);
  });
}
