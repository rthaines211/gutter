import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/widgets/page_reader.dart';

import 'fake_comic_server.dart';
import 'harness.dart';

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

  // Tap zones: TapZoneOverlay splits 800x600 into thirds via raw Listener.
  // right zone = 534-800 (advance LTR), left zone = 0-266 (retreat LTR).
  // TapZoneOverlay has a 250ms double-tap disambiguation timer (fake timer).
  // Sequence: pump(260ms) fires the 250ms tap timer → animateToPage(1,300ms)
  // starts; pump(350ms) drives the 300ms animation to completion.
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

  testWidgets('opens at initialPage and stays there (first-frame guard)',
      (tester) async {
    final h = await pumpReader(tester,
        server: server, tempDir: env, initialPage: 5);
    await settleImages(tester);
    expect(h.stateOf(tester).currentPage, 5);
    // Requested pages should center on 5, not 0.
    expect(
      server.requestsWhere((r) => r.path == '/comics/c1/pages/5'),
      isNotEmpty,
    );
    await disposeReader(tester);
  });

  testWidgets('tap zones advance and retreat (slide mode)', (tester) async {
    // ponytail: fitScreen auto-zooms landscape viewport → multi-step PanSequence,
    // first advance() pans rather than turning. Use fitHeight (identity scale,
    // single-step transform) so advance() → sequenceEnd → page turn.
    server.settings = {'page_fit': 'fitHeight'};
    final h = await pumpReader(tester, server: server, tempDir: env);
    await settleImages(tester);

    await tapRight(tester);
    await settleImages(tester, rounds: 5);
    expect(h.stateOf(tester).currentPage, 1);

    await tapLeft(tester);
    await settleImages(tester, rounds: 5);
    expect(h.stateOf(tester).currentPage, 0);
    await disposeReader(tester);
  });

  testWidgets('swipe advances page', (tester) async {
    final h = await pumpReader(tester, server: server, tempDir: env);
    await settleImages(tester);

    await tester.fling(
        find.byType(PageReader), const Offset(-400, 0), 1000);
    await tester.pump(const Duration(milliseconds: 500));
    await settleImages(tester, rounds: 5);
    expect(h.stateOf(tester).currentPage, 1);
    await disposeReader(tester);
  });

  // Regression test for the detached-controller fade bug (fixed on this
  // branch: PageView stays mounted under the fade overlay). Also verifies the
  // isFading guard: a second tap mid-fade must be swallowed, not queued.
  testWidgets('fade mode advances once per tap (isFading guard)',
      (tester) async {
    // ponytail: fitHeight → identity single-step transform → advance() → sequenceEnd → page turn
    server.settings = {'page_animation': 'fade', 'page_fit': 'fitHeight'};
    final h = await pumpReader(tester, server: server, tempDir: env);
    await settleImages(tester);

    // Two taps: first at t=0 fires onRight after 250ms tap timer → fade starts.
    // Second tap fires onRight after another 250ms → isFading guard swallows it.
    // ponytail: pump(260ms) per tap to fire the 250ms disambiguation timer.
    await tester.tapAt(const Offset(700, 300));
    await tester.pump(const Duration(milliseconds: 260));
    await tester.tapAt(const Offset(700, 300));
    await tester.pump(const Duration(milliseconds: 260));
    await tester.pump(const Duration(seconds: 1));
    await settleImages(tester, rounds: 5);

    expect(h.stateOf(tester).currentPage, 1,
        reason: 'second tap during fade must be ignored');
    await disposeReader(tester);
  });

  // Regression for two fade bugs:
  //  1. Clearing _isFading swapped Stack → bare PageView, recreating the
  //     scroll position at initialPage; the provider→controller sync saw the
  //     mismatch and re-faded forever.
  //  2. onPageChanged reset the transform to identity and animated to the
  //     fitted zoom, so the landed page shrank then zoomed back in.
  testWidgets('fade lands once, on the fitted transform, in one frame',
      (tester) async {
    // fitWidth on a 1000x1500 page in 800x600 → scale 2.0 (see tests below).
    server.settings = {'page_animation': 'fade', 'page_fit': 'fitWidth'};
    final h = await pumpReader(tester, server: server, tempDir: env);
    await settleImages(tester, rounds: 40);

    PageReaderState reader() =>
        tester.state<PageReaderState>(find.byType(PageReader));
    double scale() => tester
        .widget<InteractiveViewer>(find.byType(InteractiveViewer).first)
        .transformationController!.value.getMaxScaleOnAxis();

    // Warm page 1's decoded dimensions (real async), then come back so the
    // assertion below can run the fade on the fake clock alone.
    reader().fadeToPage(1);
    await settleImages(tester, rounds: 40);
    reader().fadeToPage(0);
    await settleImages(tester, rounds: 40);
    expect(reader().isFading, isFalse);
    expect(reader().widget.controller.page, 0);

    reader().fadeToPage(1);
    await tester.pump(); // start the fade ticker
    await tester.pump(const Duration(milliseconds: 310)); // complete it
    await tester.pump(); // .then → jumpToPage + onPageChanged; overlay removed
    expect(reader().isFading, isFalse);
    expect(scale(), moreOrLessEquals(2.0, epsilon: 0.05),
        reason: 'transform must be applied instantly when the fade ends');

    // No re-fade loop: a second later the controller still sits on page 1.
    await tester.pump(const Duration(seconds: 1));
    expect(reader().isFading, isFalse);
    expect(reader().widget.controller.page, 1);
    expect(h.stateOf(tester).currentPage, 1);
    await disposeReader(tester);
  });

  testWidgets('none mode jumps instantly', (tester) async {
    // ponytail: fitHeight → identity single-step transform → advance() → sequenceEnd → page turn
    server.settings = {'page_animation': 'none', 'page_fit': 'fitHeight'};
    final h = await pumpReader(tester, server: server, tempDir: env);
    await settleImages(tester);

    // ponytail: 250ms tap disambiguation timer must fire before jumpToPage runs.
    await tester.tapAt(const Offset(700, 300));
    await tester.pump(const Duration(milliseconds: 260));
    expect(h.stateOf(tester).currentPage, 1);
    await disposeReader(tester);
  });

  testWidgets('fitScreen auto-zooms narrow portrait page in landscape viewport',
      (tester) async {
    // ponytail: testWidgets viewport is 800x600 (landscape). A 1000x1500
    // portrait page renders at containRect.width=400 (half the viewport).
    // fitScreen auto-zooms narrow pages in landscape (width < 95% of viewport):
    // scale = viewportWidth / containRect.width = 800/400 = 2.0.
    // This is intentional behavior; the test verifies the auto-zoom fires.
    await pumpReader(tester, server: server, tempDir: env);
    await settleImages(tester, rounds: 40);

    final iv = tester
        .widget<InteractiveViewer>(find.byType(InteractiveViewer).first);
    expect(iv.transformationController!.value.getMaxScaleOnAxis(),
        moreOrLessEquals(2.0, epsilon: 0.05));
    await disposeReader(tester);
  });

  testWidgets('fitWidth applies 2x scale for 1000x1500 page on 800x600',
      (tester) async {
    server.settings = {'page_fit': 'fitWidth'};
    await pumpReader(tester, server: server, tempDir: env);
    // Extra rounds: onImageLoaded fires via addPostFrameCallback after
    // CachedNetworkImage decodes, then _recalculateTransforms runs setState.
    await settleImages(tester, rounds: 40);

    final iv = tester
        .widget<InteractiveViewer>(find.byType(InteractiveViewer).first);
    expect(iv.transformationController!.value.getMaxScaleOnAxis(),
        moreOrLessEquals(2.0, epsilon: 0.05));
    await disposeReader(tester);
  });

  testWidgets('page is opacity-gated until image loads', (tester) async {
    await pumpReader(tester, server: server, tempDir: env);
    // INVARIANT: Before image decode (imageBuilder), no RawImage from CachedNetworkImage
    // is displayed. CachedNetworkImage only mounts RawImage once bytes decode and
    // imageBuilder is called. Before that, the placeholder (CircularProgressIndicator)
    // is shown. After image loads, Opacity(1.0) gate is set to true by readyPages.
    expect(
        find.descendant(
            of: find.byType(PageReader),
            matching: find.byType(RawImage)),
        findsNothing,
        reason: 'no decoded image should be mounted before imageBuilder fires');

    await settleImages(tester, rounds: 40);
    final opacitiesAfter = tester
        .widgetList<Opacity>(find.descendant(
            of: find.byType(PageReader),
            matching: find.byType(Opacity)))
        .map((w) => w.opacity)
        .toList();

    expect(opacitiesAfter, isNotEmpty,
        reason: 'opacity gate must exist after image loads');
    expect(opacitiesAfter, contains(1.0),
        reason: 'loaded page must be shown at full opacity');
    await disposeReader(tester);
  });
}
