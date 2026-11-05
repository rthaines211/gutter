import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/models/sync_response.dart';
import 'package:comic_reader_app/screens/series_detail_screen.dart';
import 'package:comic_reader_app/widgets/reader_toolbar.dart';
import 'package:comic_reader_app/screens/reader_screen.dart';
import 'package:comic_reader_app/services/sleep_timer.dart';
import 'package:comic_reader_app/widgets/sleep_warning_overlay.dart';

import 'fake_comic_server.dart';
import 'harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory env;
  late FakeComicServer server;

  setUpAll(() async => env = await initReaderTestEnv());
  useComicServer(
    () => FakeComicServer()..comics['c1'] = List.filled(5, portraitPage),
    (s) => server = s,
    () => server,
  );
  tearDown(SleepTimer.instance.cancel);

  ReaderScreenState screen(WidgetTester tester) =>
      tester.state<ReaderScreenState>(find.byType(ReaderScreen));

  Future<void> open(WidgetTester tester) async {
    await pumpReader(tester, server: server, tempDir: env);
    await settleImages(tester);
  }

  /// Arms 1 minute, lets it fire, and returns with the recorder cleared of
  /// everything before the fire.
  Future<void> fire(WidgetTester tester) async {
    SleepTimer.instance.start(1);
    await tester.pump(const Duration(minutes: 1));
    expect(SleepTimer.instance.isOn, isFalse);
    expect(wakelockCalls.last, isFalse, reason: 'fire releases the wakelock');
    wakelockCalls.clear();
  }

  Future<void> resume(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
  }

  testWidgets('opening a comic does not start the timer', (tester) async {
    server.settings = {'sleep_timer_min': 30};
    await open(tester);
    expect(SleepTimer.instance.isOn, isFalse);
    await disposeReader(tester);
  });

  testWidgets('fire then resume restores keep-on and leaves the timer off',
      (tester) async {
    await open(tester);
    await fire(tester);
    await resume(tester);
    expect(SleepTimer.instance.isOn, isFalse);
    expect(wakelockCalls.last, isTrue);
    await disposeReader(tester);
  });

  testWidgets('fire then reader activity restores keep-on', (tester) async {
    await open(tester);
    await fire(tester);
    screen(tester).showChrome();
    await tester.pump();
    expect(wakelockCalls, [true]);
    // Only the first interaction after a fire restores.
    screen(tester).hideChrome();
    await tester.pump(const Duration(milliseconds: 300));
    expect(wakelockCalls, [true]);
    await disposeReader(tester);
  });

  testWidgets('resume after fire with keep-on off does not enable wakelock',
      (tester) async {
    server.settings = {'keep_screen_on': false};
    await open(tester);
    await fire(tester);
    await resume(tester);
    expect(wakelockCalls, isNot(contains(true)));
    await disposeReader(tester);
  });

  testWidgets('moon tap while warning visible hides the warning',
      (tester) async {
    await open(tester);
    SleepTimer.instance.start(5);
    await tester.pump(const Duration(minutes: 4));
    expect(find.byType(SleepWarningOverlay), findsOneWidget);

    screen(tester).showChrome();
    await tester.pump(const Duration(milliseconds: 260));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.tap(find.byKey(const Key('reader.sleep')));
    await tester.pump();
    expect(find.byType(SleepWarningOverlay), findsNothing);
    // 1m left -> next step above it.
    expect(SleepTimer.instance.remaining, const Duration(minutes: 5));
    await disposeReader(tester);
  });

  testWidgets('warning buttons sit above the bottom bar when chrome is up',
      (tester) async {
    await open(tester);
    screen(tester).showChrome();
    await tester.pump(const Duration(milliseconds: 260));
    await tester.pump(const Duration(milliseconds: 350));
    SleepTimer.instance.start(5);
    await tester.pump(const Duration(minutes: 4));
    await tester.pump(const Duration(milliseconds: 500)); // entrance
    expect(find.byType(SleepWarningOverlay), findsOneWidget);

    await tester.tap(find.byKey(const Key('sleep.extend')));
    await tester.pump();
    // 1m left + 15.
    expect(SleepTimer.instance.remaining,
        const Duration(minutes: 15, seconds: 59, milliseconds: 500));
    expect(find.byType(SleepWarningOverlay), findsNothing);
    await disposeReader(tester);
  });

  testWidgets('carry-over: deadline survives a reader swap', (tester) async {
    await open(tester);
    SleepTimer.instance.start(15);
    final deadline = SleepTimer.instance.deadline;

    Navigator.of(tester.element(find.byType(ReaderScreen))).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) =>
            const ReaderScreen(comicId: 'c1', comicPath: '/library/c1.cbz'),
      ),
    );
    await settleImages(tester);

    expect(SleepTimer.instance.isOn, isTrue);
    expect(SleepTimer.instance.deadline, deadline);
    await disposeReader(tester);
  });

  testWidgets('carry-over inside the lead shows the warning in the new reader',
      (tester) async {
    await open(tester);
    SleepTimer.instance.start(2);
    await tester.pump(const Duration(seconds: 70)); // 50s left, warned
    Navigator.of(tester.element(find.byType(ReaderScreen))).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) =>
            const ReaderScreen(comicId: 'c1', comicPath: '/library/c1.cbz'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(SleepWarningOverlay), findsOneWidget);
    await disposeReader(tester);
  });

  // Seeds the folder series ('library', from '/library/c1.cbz') and opens
  // series detail via the title tap, as reader_chrome_test does.
  Future<void> openSeriesDetail(WidgetTester tester, ReaderHarness h) async {
    await tester.runAsync(() => h.mirrorDb.applySync(SyncResponse(
          serverTime: 1,
          series: [
            {
              'id': 'library',
              'name': 'Library',
              'folder_path': '/library',
              'issue_count': 1,
              'cover_url': '',
              'updated_at': '2026-01-01T00:00:00Z',
              'issues': [
                {'id': 'c1', 'name': 'Issue 1.cbz', 'number': '1', 'cover_url': ''}
              ],
            }
          ],
          progress: const [],
          seriesIds: const ['library'],
          progressIds: const [],
        )));
    screen(tester).showChrome();
    await tester.pump(const Duration(milliseconds: 260));
    await tester.pump(const Duration(milliseconds: 350));
    final bar = tester.widget<ReaderTopBar>(find.byType(ReaderTopBar));
    await tester.tap(find.byWidgetPredicate(
        (w) => w is GestureDetector && w.onTap == bar.onTitleTap));
    await settleImages(tester, rounds: 5);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(SeriesDetailScreen), findsOneWidget);
  }

  testWidgets('fire under series detail: resume waits, return restores',
      (tester) async {
    server.settings = {'page_fit': 'fitHeight'};
    final h = await pumpReader(tester, server: server, tempDir: env);
    await settleImages(tester);
    await openSeriesDetail(tester, h);
    await fire(tester);

    await resume(tester);
    expect(wakelockCalls, isNot(contains(true)),
        reason: 'series page keeps the wakelock released');

    Navigator.of(tester.element(find.byType(SeriesDetailScreen))).pop();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(wakelockCalls.last, isTrue);
    await disposeReader(tester);
  });

  testWidgets('fire under a non-series route: resume restores',
      (tester) async {
    await open(tester);
    Navigator.of(tester.element(find.byType(ReaderScreen))).push(
        MaterialPageRoute<void>(builder: (_) => const Scaffold()));
    await tester.pump(const Duration(milliseconds: 400));
    await fire(tester);
    await resume(tester);
    expect(wakelockCalls.last, isTrue);
    await disposeReader(tester);
  });

  testWidgets('locked before the deadline: resume fires, then restores',
      (tester) async {
    await open(tester);
    SleepTimer.instance.start(15);
    wakelockCalls.clear();
    // The device slept: wall clock moves past the deadline, timers don't run.
    withClock(
        Clock.fixed(SleepTimer.instance.deadline!.add(const Duration(minutes: 1))),
        () {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });
    await tester.pump();
    expect(SleepTimer.instance.isOn, isFalse);
    expect(wakelockCalls, [false, true]);
    await disposeReader(tester);
  });

  testWidgets('closing the last reader cancels', (tester) async {
    await open(tester);
    SleepTimer.instance.start(15);
    await disposeReader(tester);
    expect(SleepTimer.instance.isOn, isFalse);
  });

  testWidgets('lock/unlock inside the lead re-shows the warning on resume',
      (tester) async {
    await open(tester);
    SleepTimer.instance.start(5);
    // Jump the wall clock to 0:40 left (inside the 60s lead) without
    // pumping timers, as if the device had been locked the whole time.
    withClock(
        Clock.fixed(SleepTimer.instance.deadline!
            .subtract(const Duration(seconds: 40))), () {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });
    await tester.pump();
    expect(find.byKey(const Key('sleep.extend')), findsOneWidget);
    // Cancel before disposeReader's teardown settles, so the overlay
    // unmounts cleanly rather than lingering mid-animation.
    SleepTimer.instance.cancel();
    await tester.pump();
    await disposeReader(tester);
  });

  testWidgets('picking another issue from series detail keeps the deadline',
      (tester) async {
    final h = await pumpReader(tester, server: server, tempDir: env);
    await settleImages(tester);
    await openSeriesDetail(tester, h);
    SleepTimer.instance.start(15);
    final deadline = SleepTimer.instance.deadline;

    // series_detail_panel.dart's _openIssue (fromReader path): pop with
    // SeriesDetailScreen.replacedResult, then pushReplacement a fresh
    // ReaderScreen for the picked issue.
    Navigator.of(tester.element(find.byType(SeriesDetailScreen)))
        .pop(SeriesDetailScreen.replacedResult);
    await tester.pump();
    Navigator.of(tester.element(find.byType(ReaderScreen))).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) =>
            const ReaderScreen(comicId: 'c1', comicPath: '/library/c1.cbz'),
      ),
    );
    await settleImages(tester);

    expect(SleepTimer.instance.isOn, isTrue);
    expect(SleepTimer.instance.deadline, deadline);
    await disposeReader(tester);
  });
}
