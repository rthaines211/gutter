import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/models/sync_response.dart';
import 'package:comic_reader_app/providers/accent_provider.dart';
import 'package:comic_reader_app/providers/settings_provider.dart';
import 'package:comic_reader_app/screens/reader_screen.dart';
import 'package:comic_reader_app/screens/series_detail_screen.dart';
import 'package:comic_reader_app/widgets/filmstrip_scrubber.dart';
import 'package:comic_reader_app/widgets/issue_grid_view.dart';
import 'package:comic_reader_app/widgets/issue_list_view.dart';
import 'package:comic_reader_app/widgets/page_grid_overlay.dart';
import 'package:comic_reader_app/widgets/page_reader.dart';
import 'package:comic_reader_app/widgets/reader_aa_panel.dart';
import 'package:comic_reader_app/widgets/reader_more_menu.dart';
import 'package:comic_reader_app/widgets/reader_toolbar.dart';

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

  testWidgets('reader content waits for async settings (no default flash)', (
    tester,
  ) async {
    server.settingsDelay = const Duration(milliseconds: 300);
    await pumpReader(tester, server: server, tempDir: env);
    await tester.pump(const Duration(milliseconds: 50));

    // CLAUDE.md: "Wait for settingsProvider before showing reader content,
    // otherwise default settings flash then jump."
    // line 818 in reader_screen.dart: `if (settingsAsync.isLoading || readerAsync.isLoading)`
    // returns early — if this fails it means settings are not being gated properly.
    expect(
      find.byType(PageReader),
      findsNothing,
      reason: 'reader must not render with default settings while loading',
    );

    await settleImages(tester);
    expect(find.byType(PageReader), findsOneWidget);
    await disposeReader(tester);
  });

  ReaderScreenState screen(WidgetTester tester) =>
      tester.state<ReaderScreenState>(find.byType(ReaderScreen));

  // Lets the 250ms tap disambiguation timer fire and the 200ms bar animation run.
  Future<void> settleTap(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 260));
    await tester.pump(const Duration(milliseconds: 350));
  }

  Matrix4 transform(WidgetTester tester) => tester
      .widget<InteractiveViewer>(find.byType(InteractiveViewer).first)
      .transformationController!
      .value;

  // Many small moves, like a finger: a single jump is eaten by the pan slop.
  Future<void> dragUp(WidgetTester tester) => tester.timedDragFrom(
      const Offset(400, 450), const Offset(0, -150), const Duration(milliseconds: 300));

  // fitHeight: 1000x1500 on 800x600 is a single identity step, so taps and
  // swipes aren't absorbed by auto-zoom stepping.
  Future<ReaderHarness> open(WidgetTester tester, {String fit = 'fitHeight'}) async {
    server.settings = {...server.settings, 'page_fit': fit};
    final h = await pumpReader(tester, server: server, tempDir: env);
    await settleImages(tester);
    return h;
  }

  testWidgets('swipe up shows toolbar + scrubber', (tester) async {
    await open(tester);
    await dragUp(tester);
    await settleTap(tester);
    expect(find.byType(ReaderTopBar), findsOneWidget);
    expect(find.byType(FilmstripScrubber), findsOneWidget);

    // No auto-hide: the bar waits for a page tap, page turn, or scroll.
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(ReaderTopBar), findsOneWidget,
        reason: 'toolbar must not hide on its own');
    await disposeReader(tester);
  });

  testWidgets('centre tap does not show toolbar (paged)', (tester) async {
    await open(tester);
    await tester.tapAt(const Offset(400, 300));
    await settleTap(tester);
    expect(find.byType(ReaderTopBar), findsNothing);
    await disposeReader(tester);
  });

  testWidgets(
      'tap on right third while toolbar visible hides it and stays on the same page',
      (tester) async {
    final h = await open(tester);
    screen(tester).showChrome();
    await settleTap(tester);
    expect(find.byType(ReaderTopBar), findsOneWidget);

    await tester.tapAt(const Offset(700, 300));
    await settleTap(tester);
    expect(find.byType(ReaderTopBar), findsNothing);
    expect(h.stateOf(tester).currentPage, 0);
    await disposeReader(tester);
  });

  testWidgets('horizontal swipe turns page and hides toolbar', (tester) async {
    final h = await open(tester);
    screen(tester).showChrome();
    await settleTap(tester);
    expect(find.byType(ReaderTopBar), findsOneWidget);

    await tester.flingFrom(const Offset(600, 300), const Offset(-400, 0), 1500);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(h.stateOf(tester).currentPage, 1);
    expect(find.byType(ReaderTopBar), findsNothing);
    await disposeReader(tester);
  });

  testWidgets('scroll mode: centre tap shows toolbar', (tester) async {
    server.settings = {'reading_mode': 'scroll'};
    await pumpReader(tester, server: server, tempDir: env);
    await settleImages(tester);
    await tester.tapAt(const Offset(400, 300));
    await settleTap(tester);
    expect(find.byType(ReaderTopBar), findsOneWidget);
    await disposeReader(tester);
  });

  testWidgets('after pinch zoom, vertical drag pans and does not show toolbar',
      (tester) async {
    await open(tester);
    final center = tester.getCenter(find.byType(InteractiveViewer).first);
    final g1 = await tester.startGesture(center - const Offset(30, 0));
    final g2 = await tester.startGesture(center + const Offset(30, 0));
    await g1.moveBy(const Offset(-90, 0));
    await g2.moveBy(const Offset(90, 0));
    await g1.up();
    await g2.up();
    await tester.pump(const Duration(milliseconds: 200));
    expect(transform(tester).getMaxScaleOnAxis(), greaterThan(1.2),
        reason: 'pinch must zoom in');

    final before = transform(tester).getTranslation();
    await dragUp(tester);
    await settleTap(tester);
    expect((transform(tester).getTranslation() - before).y, lessThan(-50),
        reason: 'off-step: one-finger vertical drag pans');
    expect(find.byType(ReaderTopBar), findsNothing);
    await disposeReader(tester);
  });

  testWidgets('fitWidth step: vertical drag shows toolbar and does not pan',
      (tester) async {
    // fitWidth on 800x600: scale 2.0, so ZoomWrapper would pan if allowed.
    await open(tester, fit: 'fitWidth');
    expect(transform(tester).getMaxScaleOnAxis(), moreOrLessEquals(2.0, epsilon: 0.1));
    // Rebuild the page so ZoomWrapper's pan flag reflects the 2.0 scale
    // rather than the 1.0 it was first built at.
    screen(tester).showChrome();
    await settleTap(tester);
    screen(tester).hideChrome();
    await settleTap(tester);
    expect(find.byType(ReaderTopBar), findsNothing);

    final before = transform(tester).getTranslation();
    await dragUp(tester);
    await settleTap(tester);
    expect((transform(tester).getTranslation() - before).length, lessThan(1),
        reason: 'on a step, one-finger vertical drags must not pan');
    expect(find.byType(ReaderTopBar), findsOneWidget);
    await disposeReader(tester);
  });

  testWidgets('paper theme renders white background', (tester) async {
    server.settings = {'theme': 'paper'};
    await pumpReader(tester, server: server, tempDir: env);
    await settleImages(tester);
    final scaffold = tester.widget<Scaffold>(find
        .descendant(of: find.byType(ReaderScreen), matching: find.byType(Scaffold))
        .first);
    expect(scaffold.backgroundColor, Colors.white);
    await disposeReader(tester);
  });

  testWidgets('scrubber drag changes page', (tester) async {
    final h = await pumpReader(tester, server: server, tempDir: env);
    await settleImages(tester);

    screen(tester).showChrome();
    await settleTap(tester);

    // FilmstripScrubber contains a Slider; drag it right to advance pages.
    // ponytail: drag on the Slider widget rather than raw scrubber to avoid
    // hitting the thumbnail area; onPageSelected fires on drag end.
    await tester.drag(find.byType(Slider), const Offset(300, 0));
    await tester.pump(const Duration(milliseconds: 500));
    await settleImages(tester, rounds: 5);

    expect(h.stateOf(tester).currentPage, greaterThan(0));
    await disposeReader(tester);
  });

  testWidgets('dragging the thumbnail strip scrolls it, not the reader',
      (tester) async {
    final h = await open(tester);
    screen(tester).showChrome();
    await settleTap(tester);
    final strip = find.descendant(
        of: find.byType(FilmstripScrubber), matching: find.byType(ListView));
    expect(strip, findsOneWidget);
    for (final dx in [-300.0, 300.0, -300.0]) {
      await tester.timedDrag(strip, Offset(dx, 0), const Duration(milliseconds: 200));
      await settleTap(tester);
    }
    expect(h.stateOf(tester).currentPage, 0);
    expect(find.byType(ReaderTopBar), findsOneWidget,
        reason: 'a strip drag must not toggle the chrome');
    await disposeReader(tester);
  });

  // Seeds the mirror with the reader's folder series ('library', from
  // '/library/c1.cbz') holding c1 and c2, then opens Issue details via the
  // title tap.
  Future<void> openIssueDetailsWithSeries(
      WidgetTester tester, ReaderHarness h) async {
    Map<String, dynamic> issue(String id, String n) =>
        {'id': id, 'name': 'Issue $n.cbz', 'number': n, 'cover_url': ''};
    await tester.runAsync(() => h.mirrorDb.applySync(SyncResponse(
          serverTime: 1,
          series: [
            {
              'id': 'library',
              'name': 'Library',
              'folder_path': '/library',
              'issue_count': 2,
              'cover_url': '',
              'updated_at': '2026-01-01T00:00:00Z',
              'issues': [issue('c1', '1'), issue('c2', '2')],
            }
          ],
          progress: const [],
          seriesIds: const ['library'],
          progressIds: const [],
        )));
    screen(tester).showChrome();
    await settleTap(tester);
    final bar = tester.widget<ReaderTopBar>(find.byType(ReaderTopBar));
    await tester.tap(find.byWidgetPredicate(
        (w) => w is GestureDetector && w.onTap == bar.onTitleTap));
    await settleImages(tester, rounds: 5);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(SeriesDetailScreen), findsOneWidget);
  }

  for (final target in ['c2', 'c1']) {
    testWidgets('opening issue $target from issue details replaces the reader',
        (tester) async {
      server.comics['c2'] = List.filled(10, portraitPage);
      server.settings = {'page_fit': 'fitHeight'};
      final modes = <String>[];
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'SystemChrome.setEnabledSystemUIMode') {
          modes.add(call.arguments as String);
        }
        return null;
      });
      addTearDown(() =>
          messenger.setMockMethodCallHandler(SystemChannels.platform, null));
      final h = await pumpReader(tester, server: server, tempDir: env, initialPage: 3);
      await settleImages(tester);
      await openIssueDetailsWithSeries(tester, h);
      await settleImages(tester, rounds: 5);

      final row = find.byWidgetPredicate(
          (w) =>
              (w is IssueListRow && w.issue.id == target) ||
              (w is IssueGridTile && w.issue.id == target),
          );
      await tester.scrollUntilVisible(row, 200,
          scrollable: find
              .descendant(
                  of: find.byType(SeriesDetailScreen),
                  matching: find.byWidgetPredicate((w) =>
                      w is Scrollable && w.axisDirection == AxisDirection.down))
              .first);
      await tester.pump();
      modes.clear();
      await tester.tap(row);
      await tester.pump();
      // Stands in for reader B's images: must survive A's dispose.
      const sentinel = 'reader-b-image';
      PaintingBinding.instance.imageCache.putIfAbsent(sentinel,
          () => OneFrameImageStreamCompleter(Completer<ImageInfo>().future));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await settleImages(tester, rounds: 5);

      expect(modes, ['SystemUiMode.immersive'],
          reason: "only B's initState sets the UI mode: A, being replaced, "
              'neither re-arms on pop nor restores edgeToEdge on dispose');
      expect(PaintingBinding.instance.imageCache.containsKey(sentinel), isTrue,
          reason: "A's dispose must not clear B's image cache");
      expect(find.byType(SeriesDetailScreen, skipOffstage: false), findsNothing);
      expect(find.byType(ReaderScreen, skipOffstage: false), findsOneWidget,
          reason: 'the series page and the old reader are both replaced');
      expect(tester.widget<ReaderScreen>(find.byType(ReaderScreen)).comicId,
          target);
      await disposeReader(tester);
    });
  }

  testWidgets('issue details shows the status bar; back restores immersive',
      (tester) async {
    final modes = <String>[];
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'SystemChrome.setEnabledSystemUIMode') {
        modes.add(call.arguments as String);
      }
      return null;
    });
    addTearDown(() =>
        messenger.setMockMethodCallHandler(SystemChannels.platform, null));
    server.settings = {'page_fit': 'fitHeight'};
    final h = await pumpReader(tester, server: server, tempDir: env);
    await settleImages(tester);
    expect(modes.last, 'SystemUiMode.immersive');
    await openIssueDetailsWithSeries(tester, h);
    expect(modes.last, 'SystemUiMode.edgeToEdge');

    Navigator.of(tester.element(find.byType(SeriesDetailScreen))).pop();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(modes.last, 'SystemUiMode.immersive');
    await disposeReader(tester);
  });

  testWidgets('issue details opens over the reader; back returns to the same page',
      (tester) async {
    server.settings = {'page_fit': 'fitHeight'};
    final h = await pumpReader(tester, server: server, tempDir: env, initialPage: 3);
    await settleImages(tester);
    expect(h.stateOf(tester).currentPage, 3);
    screen(tester).showChrome();
    await settleTap(tester);

    final bar = tester.widget<ReaderTopBar>(find.byType(ReaderTopBar));
    expect(bar.onTitleTap, isNotNull);
    await tester.tap(find.byWidgetPredicate(
        (w) => w is GestureDetector && w.onTap == bar.onTitleTap));
    await settleImages(tester, rounds: 5);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(SeriesDetailScreen), findsOneWidget);
    expect(find.byType(ReaderScreen, skipOffstage: false), findsOneWidget,
        reason: 'the reader stays under the series page');

    Navigator.of(tester.element(find.byType(SeriesDetailScreen))).pop();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(SeriesDetailScreen), findsNothing);
    expect(find.byType(ReaderScreen), findsOneWidget);
    expect(h.stateOf(tester).currentPage, 3);
    expect(find.byType(ReaderTopBar), findsNothing,
        reason: 'chrome was hidden before leaving');
    await disposeReader(tester);
  });

  testWidgets('live settings change switches fit mode without reopening', (
    tester,
  ) async {
    // ponytail: start from fitHeight (identity, scale 1.0) to avoid auto-zoom
    // confusion from fitScreen. Derivation on 800x600 viewport, 1000x1500 page:
    //   containRect (BoxFit.contain, imageAspect=0.667 < viewportAspect=1.333):
    //     height=600, width=400, left=200, top=0.
    //   fitHeight scale = viewportH / containRect.h = 600/600 = 1.0  ← baseline
    //   fitWidth  scale = viewportW / containRect.w = 800/400 = 2.0  ← after switch
    server.settings = {'page_fit': 'fitHeight'};
    final h = await pumpReader(tester, server: server, tempDir: env);
    // The page must be in first: identity reads 1.0 before it loads too.
    await settleUntil(tester, () => pageReady(tester));

    double scale() => tester
        .widget<InteractiveViewer>(find.byType(InteractiveViewer).first)
        .transformationController!
        .value
        .getMaxScaleOnAxis();
    expect(scale(), moreOrLessEquals(1.0, epsilon: 0.05));

    final container = h.containerOf(tester);
    final current = container.read(settingsProvider).value!;
    await tester.runAsync(
      () => container
          .read(settingsProvider.notifier)
          .save(current.copyWith(pageFit: 'fitWidth')),
    );
    await settleUntil(tester, () => (scale() - 2.0).abs() < 0.1);

    expect(
      scale(),
      moreOrLessEquals(2.0, epsilon: 0.1),
      reason: '1000x1500 page on 800x600: fitWidth scale = 2.0',
    );
    await disposeReader(tester);
  });

  Future<void> frames(WidgetTester tester, [int n = 8]) async {
    for (var i = 0; i < n; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('Aa opens settings panel on tablet and phone', (tester) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1;
    for (final size in const [Size(1024, 1366), Size(390, 844)]) {
      tester.view.physicalSize = size;
      await pumpReader(tester, server: server, tempDir: env);
      await settleImages(tester);
      screen(tester).showChrome();
      await settleTap(tester);
      await tester.tap(find.bySemanticsLabel('Reader settings'));
      await frames(tester);
      expect(find.byType(ReaderAaPanel), findsOneWidget, reason: '$size');
      await disposeReader(tester);
    }
  });

  testWidgets('More → All pages opens page grid', (tester) async {
    await open(tester);
    screen(tester).showChrome();
    await settleTap(tester);
    await tester.tap(find.bySemanticsLabel('More'));
    await frames(tester);
    await tester.tap(find.text('All pages'));
    await frames(tester, 12);
    expect(find.byType(PageGridOverlay), findsOneWidget);
    await disposeReader(tester);
  });

  testWidgets('Clip a panel: the armed tap neither turns the page nor shows chrome',
      (tester) async {
    final h = await open(tester);
    screen(tester).showChrome();
    await settleTap(tester);
    await tester.tap(find.bySemanticsLabel('More'));
    await frames(tester);
    await tester.tap(find.text('Clip a panel'));
    await frames(tester);
    expect(find.text('Tap a panel to clip it'), findsOneWidget);
    await settleTap(tester);
    expect(find.byType(ReaderTopBar), findsNothing, reason: 'arming hides chrome');

    await tester.tapAt(const Offset(700, 300)); // right third = next page
    await settleTap(tester);
    await settleImages(tester, rounds: 5);
    expect(h.stateOf(tester).currentPage, 0);
    expect(find.byType(ReaderTopBar), findsNothing);

    // One-shot: the next tap is a normal page turn again.
    await tester.tapAt(const Offset(700, 300));
    await settleTap(tester);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(h.stateOf(tester).currentPage, 1);
    await disposeReader(tester);
  });

  testWidgets('the user accent reaches the bottom bar', (tester) async {
    server.settings = {'page_fit': 'fitHeight'};
    await pumpReader(tester, server: server, tempDir: env, extraOverrides: [
      accentProvider.overrideWith(_PinkAccent.new),
    ]);
    await settleImages(tester);
    screen(tester).showChrome();
    await settleTap(tester);
    expect(tester.widget<FilmstripScrubber>(find.byType(FilmstripScrubber)).accent,
        _pink);
    await disposeReader(tester);
  });

  Future<void> pinchOut(WidgetTester tester) async {
    final center = tester.getCenter(find.byType(InteractiveViewer).first);
    final g1 = await tester.startGesture(center - const Offset(30, 0));
    final g2 = await tester.startGesture(center + const Offset(30, 0));
    await g1.moveBy(const Offset(-90, 0));
    await g2.moveBy(const Offset(90, 0));
    await g1.up();
    await g2.up();
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('zoom lock: after a page turn, vertical drag pans the locked zoom',
      (tester) async {
    server.settings = {'zoom_lock': true};
    final h = await open(tester);
    await pinchOut(tester);
    expect(transform(tester).getMaxScaleOnAxis(), greaterThan(1.2));

    await tester.tapAt(const Offset(700, 300)); // right edge = next page
    await settleTap(tester);
    await settleImages(tester, rounds: 5);
    expect(h.stateOf(tester).currentPage, 1);
    expect(transform(tester).getMaxScaleOnAxis(), greaterThan(1.2),
        reason: 'the locked zoom carries over to the new page');

    final before = transform(tester).getTranslation();
    await dragUp(tester);
    await settleTap(tester);
    expect((transform(tester).getTranslation() - before).y, lessThan(-50),
        reason: 'a locked zoom pans with one finger');
    expect(find.byType(ReaderTopBar), findsNothing);
    await disposeReader(tester);
  });

  testWidgets('zoom lock: swipe up on a fitWidth step keeps showing chrome',
      (tester) async {
    server.settings = {'zoom_lock': true};
    await open(tester, fit: 'fitWidth');
    // Under a loaded full-suite run the page can land after open()'s settle.
    for (var i = 0; i < 10 && transform(tester).getMaxScaleOnAxis() < 1.5; i++) {
      await settleImages(tester, rounds: 5);
    }
    expect(transform(tester).getMaxScaleOnAxis(), moreOrLessEquals(2.0, epsilon: 0.1));
    for (var i = 0; i < 2; i++) {
      await dragUp(tester);
      await settleTap(tester);
      expect(find.byType(ReaderTopBar), findsOneWidget, reason: 'swipe ${i + 1}');
      expect(screen(tester).zoomLocked, isFalse,
          reason: 'a reader-set step is never a locked zoom');
      screen(tester).hideChrome();
      await settleTap(tester);
    }
    await disposeReader(tester);
  });

  testWidgets('fitWidth step: an up-flick shows chrome without stepping or turning',
      (tester) async {
    final h = await open(tester, fit: 'fitWidth');
    screen(tester).showChrome();
    await settleTap(tester);
    screen(tester).hideChrome();
    await settleTap(tester);

    final before = transform(tester).clone();
    // Up-flick with a little leftward drift: fast enough horizontally to
    // read as a right-edge overscroll if direction weren't checked.
    // ZoomWrapper times its velocity with the wall clock, so the moves need
    // real time between them.
    await tester.runAsync(() async {
      final g = await tester.startGesture(const Offset(450, 500));
      for (var i = 0; i < 6; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 8));
        await g.moveBy(const Offset(-10, -50));
      }
      await g.up();
    });
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(ReaderTopBar), findsOneWidget);
    expect(h.stateOf(tester).currentPage, 0);
    expect((transform(tester).getTranslation() - before.getTranslation()).length,
        lessThan(1),
        reason: 'the flick must not advance the pan step');
    await disposeReader(tester);
  });

  testWidgets('remote page turn closes the iPad Aa popover and the more menu',
      (tester) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1024, 1366);
    final commands = StreamController<Map<String, dynamic>>.broadcast();
    addTearDown(commands.close);
    server.settings = {'page_fit': 'fitHeight'};
    final h = await pumpReader(tester,
        server: server,
        tempDir: env,
        remoteCommands: () => commands.stream);
    await settleImages(tester);

    screen(tester).showChrome();
    await settleTap(tester);
    await tester.tap(find.bySemanticsLabel('Reader settings'));
    await frames(tester);
    expect(find.byType(ReaderAaPanel), findsOneWidget);
    commands.add({'type': 'next'});
    await frames(tester);
    await settleImages(tester, rounds: 5);
    expect(h.stateOf(tester).currentPage, 1);
    expect(find.byType(ReaderAaPanel), findsNothing);

    screen(tester).showChrome();
    await settleTap(tester);
    await tester.tap(find.bySemanticsLabel('More'));
    await frames(tester);
    expect(find.byType(ReaderMoreMenu), findsOneWidget);
    commands.add({'type': 'next'});
    await frames(tester);
    await settleImages(tester, rounds: 5);
    expect(h.stateOf(tester).currentPage, 2);
    expect(find.byType(ReaderMoreMenu), findsNothing);
    expect(find.byType(ReaderScreen), findsOneWidget,
        reason: 'closing the menu must not pop the reader');
    await disposeReader(tester);
  });

  List<RecordedRequest> flagPuts() =>
      server.requestsWhere((r) => r.method == 'PUT' && r.path.endsWith('/flag'));

  Future<void> twoFingerTap(WidgetTester tester, {double move = 0}) async {
    final a = await tester.startGesture(const Offset(300, 300), pointer: 41);
    final b = await tester.startGesture(const Offset(500, 300), pointer: 42);
    if (move > 0) {
      await a.moveBy(Offset(-move, 0));
      await b.moveBy(Offset(move, 0));
    }
    await a.up();
    await b.up();
    await frames(tester);
  }

  testWidgets('Flag page (panel zoom) asks why, then PUTs the reason', (tester) async {
    server.settings = {'page_fit': 'fitHeight', 'zoom_mode': 'panels'};
    final h = await open(tester);
    h.notifierOf(tester).goToPage(3);
    await frames(tester);
    screen(tester).showChrome();
    await settleTap(tester);
    await tester.tap(find.bySemanticsLabel('More'));
    await frames(tester);
    await tester.tap(find.text('Flag page'));
    await frames(tester);
    expect(find.text("What's wrong on page 4?"), findsOneWidget);
    expect(find.text('A balloon is missing'), findsNothing, reason: 'panel zoom offers panel reasons');
    await tester.tap(find.text('A panel is cut wrong'));
    await settleImages(tester, rounds: 5); // lets the real HTTP PUT complete
    expect(flagPuts(), hasLength(1));
    expect(flagPuts().single.path, '/comics/c1/pages/3/flag');
    expect(flagPuts().single.jsonBody, {'reason': 'panel_cut', 'zoom': 'panels'});
    expect(find.text('Flagged page 4'), findsOneWidget);
    await disposeReader(tester);
  });

  testWidgets('two-finger tap (bubble zoom) opens the card without turning the page; Cancel flags nothing',
      (tester) async {
    server.settings = {'page_fit': 'fitHeight', 'zoom_mode': 'bubbles'};
    final h = await open(tester);
    final before = h.stateOf(tester).currentPage;
    await twoFingerTap(tester);
    await settleImages(tester, rounds: 3);
    expect(find.text('A balloon is missing'), findsOneWidget);
    expect(find.text('A panel is missing'), findsNothing);
    expect(h.stateOf(tester).currentPage, before);
    await tester.tap(find.text('Cancel'));
    await settleImages(tester, rounds: 3);
    await tester.pump(const Duration(milliseconds: 400)); // dialog exit transition
    expect(find.text('A balloon is missing'), findsNothing);
    expect(find.text("What's wrong on page ${before + 1}?"), findsNothing);
    expect(flagPuts(), isEmpty);
    await disposeReader(tester);
  });

  testWidgets('a pinch is not a two-finger tap', (tester) async {
    server.settings = {'page_fit': 'fitHeight', 'zoom_mode': 'panels'};
    await open(tester);
    await twoFingerTap(tester, move: 60);
    await settleImages(tester, rounds: 3);
    expect(find.text('Order is wrong'), findsNothing);
    await disposeReader(tester);
  });

  testWidgets('zoom off: no Flag page item and two-finger tap does nothing', (tester) async {
    server.settings = {'page_fit': 'fitHeight', 'zoom_mode': 'off'};
    await open(tester);
    await twoFingerTap(tester);
    await settleImages(tester, rounds: 3);
    expect(find.text('Order is wrong'), findsNothing);
    screen(tester).showChrome();
    await settleTap(tester);
    await tester.tap(find.bySemanticsLabel('More'));
    await frames(tester);
    expect(find.text('All pages'), findsOneWidget);
    expect(find.text('Flag page'), findsNothing);
    await disposeReader(tester);
  });

  testWidgets('scroll mode: the more menu has no Clip a panel', (tester) async {
    server.settings = {'reading_mode': 'scroll'};
    await pumpReader(tester, server: server, tempDir: env);
    await settleImages(tester);
    screen(tester).showChrome();
    await settleTap(tester);
    await tester.tap(find.bySemanticsLabel('More'));
    await frames(tester);
    expect(find.text('All pages'), findsOneWidget);
    expect(find.text('Clip a panel'), findsNothing);
    await disposeReader(tester);
  });

  testWidgets('Clip a panel: a swipe disarms, so the next tap turns the page',
      (tester) async {
    final h = await open(tester);
    screen(tester).showChrome();
    await settleTap(tester);
    await tester.tap(find.bySemanticsLabel('More'));
    await frames(tester);
    await tester.tap(find.text('Clip a panel'));
    await frames(tester);
    await settleTap(tester);

    await dragUp(tester);
    await settleTap(tester);
    await tester.tapAt(const Offset(700, 300));
    await settleTap(tester);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(h.stateOf(tester).currentPage, 1);
    await disposeReader(tester);
  });
}

const _pink = Color(0xFFFF2D95);

class _PinkAccent extends AccentNotifier {
  @override
  Future<Color> build() async => _pink;
}
