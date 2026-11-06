import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/providers/settings_provider.dart';
import 'package:comic_reader_app/widgets/bubble_pop_overlay.dart';
import 'package:comic_reader_app/widgets/panel_dim_overlay.dart';

import 'fake_comic_server.dart';
import 'harness.dart';

Map<String, dynamic> panelSidecar() => {
  'v': 1,
  'w': 1000,
  'h': 1500,
  'bubbles': [],
  'panels': [
    [0, 0, 500, 750],
    [500, 0, 1000, 750],
    [0, 750, 1000, 1500],
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

  // Same timing as bubble_zoom_flow_test: 250 ms double-tap window, 300 ms page slide.
  Future<void> tapRight(WidgetTester tester) async {
    await tester.tapAt(const Offset(700, 300));
    await tester.pump(const Duration(milliseconds: 260));
    await tester.pump(const Duration(milliseconds: 350));
  }

  Future<void> settleUntil(
    WidgetTester tester,
    bool Function() done, {
    int maxRounds = 300,
  }) async {
    for (var i = 0; i < maxRounds && !done(); i++) {
      await settleImages(tester, rounds: 1);
    }
  }

  bool pageReady(WidgetTester tester) => tester
      .widgetList<Opacity>(
        find.ancestor(of: find.byType(Image), matching: find.byType(Opacity)),
      )
      .any((o) => o.opacity == 1);

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
    return f.evaluate().isEmpty ? null : tester.widget<BubblePopOverlay>(f).label;
  }

  Rect? dimHole(WidgetTester tester) {
    final f = find.byType(PanelDimOverlay);
    return f.evaluate().isEmpty ? null : tester.widget<PanelDimOverlay>(f).hole;
  }

  // The default 800 x 600 test surface is at the tablet breakpoint: pop-out mode.
  testWidgets('iPad: taps pop panels out in order, then turn the page', (tester) async {
    server.settings = {'zoom_mode': 'panels', 'page_fit': 'fitHeight'};
    server.bubbles['c1'] = {0: panelSidecar()};
    final h = await pumpReader(tester, server: server, tempDir: env);
    await settleImages(tester);
    await waitForBubbles(tester);
    expect(shown(tester), isNull);
    expect(dimHole(tester), isNull, reason: 'dim off by default');

    await tapRight(tester);
    expect(shown(tester), 1);
    final o = tester.widget<BubblePopOverlay>(find.byType(BubblePopOverlay));
    expect(o.parts.single.mask, isNull);
    expect(o.tail, isNull);
    expect(o.maxScale, 1.5);
    expect(o.heightCap, 0.85);
    await tapRight(tester);
    expect(shown(tester), 2);
    await tapRight(tester);
    expect(shown(tester), 3);
    expect(h.stateOf(tester).currentPage, 0);
    await tapRight(tester);
    await settleImages(tester, rounds: 5);
    expect(h.stateOf(tester).currentPage, 1);
    expect(shown(tester), isNull);
    await disposeReader(tester);
  });

  testWidgets('dim setting cuts a hole at the current panel', (tester) async {
    server.settings = {'zoom_mode': 'panels', 'panel_dim': true, 'page_fit': 'fitHeight'};
    server.bubbles['c1'] = {0: panelSidecar()};
    await pumpReader(tester, server: server, tempDir: env);
    await settleImages(tester);
    await waitForBubbles(tester);
    expect(dimHole(tester), isNull);
    await tapRight(tester);
    // the page contain-fits 400 x 600 at x = 200; panel 1 is its top-left quarter
    expect(dimHole(tester), const Rect.fromLTRB(200, 0, 400, 300));
    await disposeReader(tester);
  });

  testWidgets('a sidecar without panels keeps chunk pan: first tap turns the page', (tester) async {
    server.settings = {'zoom_mode': 'panels', 'page_fit': 'fitHeight'};
    server.bubbles['c1'] = {
      0: {'v': 1, 'w': 1000, 'h': 1500, 'bubbles': []},
    };
    final h = await pumpReader(tester, server: server, tempDir: env);
    await settleImages(tester);
    await waitForBubbles(tester);
    await tapRight(tester);
    await settleImages(tester, rounds: 5);
    expect(h.stateOf(tester).currentPage, 1);
    expect(shown(tester), isNull);
    await disposeReader(tester);
  });

  testWidgets('phone: a step zooms the page onto the panel, no pop-out', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    server.settings = {'zoom_mode': 'panels', 'page_fit': 'fitHeight'};
    server.bubbles['c1'] = {0: panelSidecar()};
    final h = await pumpReader(tester, server: server, tempDir: env);
    await settleImages(tester);
    await waitForBubbles(tester);
    await tester.tapAt(const Offset(360, 300));
    await tester.pump(const Duration(milliseconds: 260));
    await tester.pump(const Duration(milliseconds: 350));
    expect(h.stateOf(tester).currentPage, 0);
    expect(shown(tester), isNull);
    final iv = tester.widget<InteractiveViewer>(find.byType(InteractiveViewer).first);
    expect(iv.transformationController!.value.entry(0, 0), greaterThan(1.5));
    await disposeReader(tester);
  });

  for (final dim in [true, false]) {
  testWidgets('iPad: a full-width panel lifts out at its own size (dim: $dim)', (tester) async {
    // a 600 x 800 surface (tablet breakpoint is 768 wide: use landscape 800 x 600 with a
    // page that fills its height... simpler: 1000 x 1333 page on 800 x 600 contain-fits
    // 450 wide; use a page that fills the width instead: 1200 x 900 fits 800 x 600 exactly)
    server.settings = {'zoom_mode': 'panels', 'page_fit': 'fitHeight', 'panel_dim': dim};
    server.comics['c1'] = List.filled(10, const PageSpec(1200, 900));
    server.bubbles['c1'] = {
      0: {
        'v': 1, 'w': 1200, 'h': 900, 'bubbles': [],
        'panels': [[0, 0, 1200, 450], [0, 450, 600, 900], [600, 450, 1200, 900]],
      },
    };
    await pumpReader(tester, server: server, tempDir: env);
    await settleImages(tester);
    await waitForBubbles(tester);
    await tapRight(tester);
    await settleImages(tester, rounds: 5);
    expect(shown(tester), 1);
    final o = tester.widget<BubblePopOverlay>(find.byType(BubblePopOverlay));
    expect(o.minScale, 1);
    expect(o.minGrowth, 1);
    // the panel spans the whole 800 px width: drawn at its own size, dim or not
    expect(
      find.descendant(of: find.byType(BubblePopOverlay), matching: find.byType(CustomPaint)),
      findsOneWidget,
    );
    await disposeReader(tester);
  });
  }

  testWidgets('iPad: flipping dim mid-page keeps the current panel', (tester) async {
    server.settings = {'zoom_mode': 'panels', 'page_fit': 'fitHeight'};
    server.bubbles['c1'] = {0: panelSidecar()};
    final h = await pumpReader(tester, server: server, tempDir: env);
    await settleImages(tester);
    await waitForBubbles(tester);
    await tapRight(tester);
    await tapRight(tester);
    expect(shown(tester), 2);
    final container = h.containerOf(tester);
    final current = container.read(settingsProvider).value!;
    // Not awaited: save() PUTs /settings, which only completes inside settleImages' runAsync.
    container.read(settingsProvider.notifier).save(current.copyWith(panelDim: true));
    await settleImages(tester, rounds: 5);
    expect(shown(tester), 2);
    expect(dimHole(tester), const Rect.fromLTRB(400, 0, 600, 300));
    await disposeReader(tester);
  });

  testWidgets('iPad landscape: panels pop out over the fit-width page', (tester) async {
    // fitScreen on the sideways 800 x 600 surface zooms the 400-wide page to width: scale 2
    server.settings = {'zoom_mode': 'panels'};
    server.bubbles['c1'] = {0: panelSidecar()};
    final h = await pumpReader(tester, server: server, tempDir: env);
    await settleImages(tester);
    await waitForBubbles(tester);
    double scale() => tester
        .widget<InteractiveViewer>(find.byType(InteractiveViewer).first)
        .transformationController!
        .value
        .entry(0, 0);
    expect(scale(), closeTo(2, 0.01));
    await tapRight(tester);
    expect(shown(tester), 1);
    expect(scale(), closeTo(2, 0.01));
    await tapRight(tester);
    await tapRight(tester);
    expect(shown(tester), 3);
    expect(h.stateOf(tester).currentPage, 0);
    await disposeReader(tester);
  });

  testWidgets('iPad portrait: a spread steps through its panels', (tester) async {
    tester.view.physicalSize = const Size(800, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    server.settings = {'zoom_mode': 'panels'};
    server.comics['c1'] = List.filled(10, const PageSpec(2000, 1500));
    server.bubbles['c1'] = {
      0: {
        'v': 1, 'w': 2000, 'h': 1500, 'bubbles': [],
        'panels': [[0, 0, 1000, 1500], [1000, 0, 2000, 750], [1000, 750, 2000, 1500]],
      },
    };
    final h = await pumpReader(tester, server: server, tempDir: env);
    await settleImages(tester);
    await waitForBubbles(tester);
    await tapRight(tester);
    expect(shown(tester), 1);
    await tapRight(tester);
    await tapRight(tester);
    expect(shown(tester), 3);
    expect(h.stateOf(tester).currentPage, 0);
    await disposeReader(tester);
  });

  testWidgets('phone: the dim stays on while a step animates', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    server.settings = {'zoom_mode': 'panels', 'panel_dim': true, 'page_fit': 'fitHeight'};
    server.bubbles['c1'] = {0: panelSidecar()};
    await pumpReader(tester, server: server, tempDir: env);
    await settleImages(tester);
    await waitForBubbles(tester);
    await tester.tapAt(const Offset(360, 300));
    await tester.pump(const Duration(milliseconds: 260)); // the tap fires; the slide starts
    await tester.pump(const Duration(milliseconds: 100)); // a third of the way there
    expect(dimHole(tester), isNotNull, reason: 'mid-animation the hole follows the page');
    await tester.pump(const Duration(milliseconds: 350));
    expect(dimHole(tester), isNotNull);
    await disposeReader(tester);
  });
}
