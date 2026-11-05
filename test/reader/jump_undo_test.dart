import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/models/series.dart';
import 'package:comic_reader_app/providers/settings_provider.dart';
import 'package:comic_reader_app/screens/reader_screen.dart';
import 'package:comic_reader_app/widgets/floating_page_pill.dart';
import 'package:comic_reader_app/widgets/filmstrip_scrubber.dart';
import 'package:comic_reader_app/widgets/jump_back_chip.dart';

import 'fake_comic_server.dart';
import 'harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory env;
  late FakeComicServer server;

  setUpAll(() async => env = await initReaderTestEnv());
  useComicServer(
    // fitHeight: identity single-step transform, so one tap turns one page.
    () => FakeComicServer()
      ..comics['c1'] = List.filled(50, portraitPage)
      ..settings = {'page_fit': 'fitHeight'},
    (s) => server = s,
    () => server,
  );

  ReaderScreenState screen(WidgetTester tester) =>
      tester.state<ReaderScreenState>(find.byType(ReaderScreen));
  final chip = find.byType(JumpBackChip);

  /// Opens the bar, releases the scrubber on [page] (0-based), hides the bar.
  Future<void> jump(WidgetTester tester, int page) async {
    screen(tester).showChrome();
    await tester.pump(const Duration(milliseconds: 300));
    tester
        .widget<FilmstripScrubber>(find.byType(FilmstripScrubber))
        .onPageSelected(page);
    await tester.pump();
    screen(tester).hideChrome();
    await tester.pump(const Duration(milliseconds: 300));
    await settleImages(tester, rounds: 5);
  }

  Future<void> turn(WidgetTester tester) async {
    await tester.tapAt(const Offset(700, 300));
    await tester.pump(const Duration(milliseconds: 500));
    await settleImages(tester, rounds: 5);
  }

  Future<void> tapChip(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('jumpchip.action')));
    await tester.pump();
    await settleImages(tester, rounds: 5);
  }

  Future<List<int>> putPages() async => server
      .requestsWhere((r) => r.method == 'PUT' && r.path == '/reading/c1')
      .map((r) => r.jsonBody!['current_page'] as int)
      .toList();

  /// Past the 2s save debounce, plus real time for the PUT round trip.
  Future<void> waitForSave(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 3));
    await settleImages(tester, rounds: 5);
  }

  testWidgets('scrubber jump offers Back, then Forward, then Back',
      (tester) async {
    final h = await pumpReader(tester,
        server: server, tempDir: env, initialPage: 3);
    await settleImages(tester);

    await jump(tester, 19);
    expect(h.stateOf(tester).currentPage, 19);
    expect(find.text('Back to page 4'), findsOneWidget);

    await tapChip(tester);
    expect(h.stateOf(tester).currentPage, 3);
    expect(find.text('Forward to page 20'), findsOneWidget);

    await tapChip(tester);
    expect(h.stateOf(tester).currentPage, 19);
    expect(find.text('Back to page 4'), findsOneWidget);
    await disposeReader(tester);
  });

  testWidgets('chained jumps keep the original origin', (tester) async {
    final h = await pumpReader(tester,
        server: server, tempDir: env, initialPage: 3);
    await settleImages(tester);

    await jump(tester, 19);
    await jump(tester, 39);
    expect(find.text('Back to page 4'), findsOneWidget);
    await tapChip(tester);
    expect(h.stateOf(tester).currentPage, 3);
    expect(find.text('Forward to page 40'), findsOneWidget);
    await disposeReader(tester);
  });

  testWidgets('three ordinary turns hide the chip; two do not',
      (tester) async {
    await pumpReader(tester, server: server, tempDir: env, initialPage: 3);
    await settleImages(tester);

    await jump(tester, 19);
    await turn(tester);
    await turn(tester);
    expect(chip, findsOneWidget);
    await turn(tester);
    expect(chip, findsNothing);
    await disposeReader(tester);
  });

  testWidgets('× dismisses the chip', (tester) async {
    await pumpReader(tester, server: server, tempDir: env, initialPage: 3);
    await settleImages(tester);

    await jump(tester, 19);
    await tester.tap(find.byKey(const Key('jumpchip.dismiss')));
    await tester.pump();
    expect(chip, findsNothing);
    await disposeReader(tester);
  });

  testWidgets('a jump is not saved until the reader reads on',
      (tester) async {
    final h = await pumpReader(tester,
        server: server, tempDir: env, initialPage: 3);
    await settleImages(tester);
    await waitForSave(tester);

    await jump(tester, 19);
    await waitForSave(tester);
    expect((await putPages()).last, 3, reason: 'jumped-to page held back');
    final row = await tester.runAsync(
        () => h.mirrorDb.select(h.mirrorDb.progressRows).getSingle());
    expect(row!.currentPage, 3);

    await turn(tester);
    await turn(tester);
    await turn(tester);
    await waitForSave(tester);
    expect((await putPages()).last, 22, reason: 'read on: save normally');
    await disposeReader(tester);
  });

  testWidgets('closing while the chip shows saves the origin',
      (tester) async {
    final h = await pumpReader(tester,
        server: server, tempDir: env, initialPage: 3);
    await settleImages(tester);

    await jump(tester, 19);
    // Close button path: flush now, then the dispose flush of the pending
    // debounce. Both must write the origin.
    await tester.runAsync(() => h.notifierOf(tester).saveProgressNow());
    expect((await putPages()).last, 3);
    await disposeReader(tester);
    final row = await tester.runAsync(
        () => h.mirrorDb.select(h.mirrorDb.progressRows).getSingle());
    expect(row!.currentPage, 3);
  });

  testWidgets('an ordinary page turn never shows the chip', (tester) async {
    await pumpReader(tester, server: server, tempDir: env, initialPage: 3);
    await settleImages(tester);

    await turn(tester);
    expect(chip, findsNothing);
    await disposeReader(tester);
  });

  testWidgets('chip shows without chrome and sits above the bottom bar',
      (tester) async {
    await pumpReader(tester, server: server, tempDir: env, initialPage: 3);
    await settleImages(tester);

    await jump(tester, 19);
    expect(find.byType(FilmstripScrubber), findsNothing);
    expect(chip, findsOneWidget);
    final pill = find.descendant(
        of: find.byType(FloatingPagePill), matching: find.byType(ClipRRect));
    expect(tester.getRect(chip).bottom,
        lessThanOrEqualTo(tester.getRect(pill.first).top));

    screen(tester).showChrome();
    await tester.pump(const Duration(milliseconds: 300));
    expect(chip, findsOneWidget);
    expect(tester.getRect(chip).bottom,
        lessThanOrEqualTo(tester.getRect(find.byType(FilmstripScrubber)).top));
    await disposeReader(tester);
  });

  testWidgets('next issue while the chip shows keeps the old issue completed',
      (tester) async {
    server.comics['c2'] = List.filled(10, portraitPage);
    final commands = StreamController<Map<String, dynamic>>.broadcast();
    addTearDown(commands.close);
    const issues = [
      SeriesIssue(id: 'c1', name: 'Issue 1', coverUrl: '', status: 'reading'),
      SeriesIssue(id: 'c2', name: 'Issue 2', coverUrl: '', status: 'unread'),
    ];
    final h = await pumpReader(tester,
        server: server,
        tempDir: env,
        initialPage: 3,
        seriesIssues: issues,
        currentIssueIndex: 0,
        remoteCommands: () => commands.stream);
    await settleImages(tester);

    await jump(tester, 19);
    expect(chip, findsOneWidget);
    commands.add({'type': 'nextIssue'});
    await tester.pump();
    await settleImages(tester);
    await waitForSave(tester);

    expect((await putPages()).last, 50, reason: 'completion must stand');
    final row = await tester.runAsync(() => (h.mirrorDb.select(
            h.mirrorDb.progressRows)
          ..where((r) => r.comicId.equals('c1')))
        .getSingle());
    expect(row!.currentPage, 50);
    await disposeReader(tester);
  });

  testWidgets('switching to scroll mode dismisses the chip and the hold',
      (tester) async {
    final h = await pumpReader(tester,
        server: server, tempDir: env, initialPage: 3);
    await settleImages(tester);

    await jump(tester, 19);
    expect(h.notifierOf(tester).heldPage, 3);
    final container = h.containerOf(tester);
    final base = container.read(settingsProvider).value!;
    await tester.runAsync(() => container
        .read(settingsProvider.notifier)
        .save(base.copyWith(readingMode: 'scroll')));
    await settleImages(tester, rounds: 5);

    expect(chip, findsNothing);
    expect(h.notifierOf(tester).heldPage, isNull);
    await disposeReader(tester);
  });

  testWidgets('completion carries a bookmark toggled inside the debounce',
      (tester) async {
    server.comics['c2'] = List.filled(10, portraitPage);
    final commands = StreamController<Map<String, dynamic>>.broadcast();
    addTearDown(commands.close);
    const issues = [
      SeriesIssue(id: 'c1', name: 'Issue 1', coverUrl: '', status: 'reading'),
      SeriesIssue(id: 'c2', name: 'Issue 2', coverUrl: '', status: 'unread'),
    ];
    final h = await pumpReader(tester,
        server: server,
        tempDir: env,
        initialPage: 3,
        seriesIssues: issues,
        currentIssueIndex: 0,
        remoteCommands: () => commands.stream);
    await settleImages(tester);

    await jump(tester, 19);
    h.notifierOf(tester).toggleBookmark(19); // < 2s before completion
    commands.add({'type': 'nextIssue'});
    await tester.pump();
    await settleImages(tester);
    await waitForSave(tester);

    final completion = server
        .requestsWhere((r) =>
            r.method == 'PUT' &&
            r.path == '/reading/c1' &&
            r.jsonBody!['current_page'] == 50)
        .single;
    final pages = (completion.jsonBody!['bookmarks'] as List)
        .map((b) => (b as Map)['page_num'])
        .toList();
    expect(pages, [19]);
    await disposeReader(tester);
  });
}
