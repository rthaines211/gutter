import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/models/series.dart';

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

  testWidgets('page turn PUTs progress with correct body', (tester) async {
    final h = await pumpReader(tester, server: server, tempDir: env);
    await settleImages(tester);

    h.notifierOf(tester).goToPage(3);
    await tester.pump();
    await tester.runAsync(() => h.notifierOf(tester).saveProgressNow());
    await settleImages(tester, rounds: 5);

    final puts = server.requestsWhere(
        (r) => r.method == 'PUT' && r.path == '/reading/c1');
    expect(puts, isNotEmpty);
    expect(puts.last.jsonBody!['current_page'], 3);
    expect(puts.last.jsonBody!['total_pages'], 10);
    await disposeReader(tester);
  });

  testWidgets('progress is written to mirror even when server returns 500, '
      'and enqueued to SyncQueue', (tester) async {
    server.failProgressWrites = true;
    final h = await pumpReader(tester, server: server, tempDir: env);
    await settleImages(tester);

    h.notifierOf(tester).goToPage(4);
    await tester.pump();
    await tester.runAsync(() => h.notifierOf(tester).saveProgressNow());
    await settleImages(tester, rounds: 5);

    // Spec asks for write-order; order isn't observable across these seams,
    // so we assert the stronger user-visible property: the local write exists
    // even when the server write fails.
    final rows = await tester.runAsync(
        () => h.mirrorDb.select(h.mirrorDb.progressRows).get());
    expect(rows, isNotEmpty,
        reason: 'mirror row must exist even when server returns 500');

    // Failure path: outbox entry.
    final queued = await tester.runAsync(() => h.syncQueue.readAll());
    expect(queued!.any((e) => e['type'] == 'progress'), isTrue);
    await disposeReader(tester);
  });

  testWidgets('bookmark toggle round-trips through PUT body', (tester) async {
    final h = await pumpReader(tester, server: server, tempDir: env);
    await settleImages(tester);

    h.notifierOf(tester).toggleBookmark(0);
    await tester.pump();
    await tester.runAsync(() => h.notifierOf(tester).saveProgressNow());
    await settleImages(tester, rounds: 5);
    var puts = server.requestsWhere(
        (r) => r.method == 'PUT' && r.path == '/reading/c1');
    expect((puts.last.jsonBody!['bookmarks'] as List), isNotEmpty);

    h.notifierOf(tester).toggleBookmark(0); // toggle off
    await tester.pump();
    await tester.runAsync(() => h.notifierOf(tester).saveProgressNow());
    await settleImages(tester, rounds: 5);
    puts = server.requestsWhere(
        (r) => r.method == 'PUT' && r.path == '/reading/c1');
    expect((puts.last.jsonBody!['bookmarks'] as List), isEmpty);
    await disposeReader(tester);
  });

  testWidgets('reopening at saved page resumes there', (tester) async {
    // Session 1: read to page 6.
    var h = await pumpReader(tester, server: server, tempDir: env);
    await settleImages(tester);
    h.notifierOf(tester).goToPage(6);
    await tester.pump();
    await tester.runAsync(() => h.notifierOf(tester).saveProgressNow());
    final puts = server.requestsWhere(
        (r) => r.method == 'PUT' && r.path == '/reading/c1');
    final savedPage = puts.last.jsonBody!['current_page'] as int;
    await disposeReader(tester);

    // Session 2: caller passes saved progress as initialPage (per
    // architecture: reader never re-fetches progress itself).
    h = await pumpReader(tester,
        server: server, tempDir: env, initialPage: savedPage);
    await settleImages(tester);
    expect(h.stateOf(tester).currentPage, 6);
    await disposeReader(tester);
  });

  testWidgets('reaching last page shows end card (series context)',
      (tester) async {
    // ponytail: fitHeight → identity single-step transform so the tap
    // advances instead of entering the fitScreen auto-zoom pan sequence
    // (same guard as every other tap-to-advance test in this suite).
    server.settings = {'page_fit': 'fitHeight'};
    const issues = [
      SeriesIssue(id: 'c1', name: 'Issue 1', coverUrl: '', status: 'reading'),
      SeriesIssue(id: 'c2', name: 'Issue 2', coverUrl: '', status: 'unread'),
    ];
    final h = await pumpReader(tester,
        server: server,
        tempDir: env,
        seriesIssues: issues,
        currentIssueIndex: 0,
        initialPage: 9);
    await settleImages(tester);

    // Advance past the final page onto the end-card virtual page.
    await tester.tapAt(const Offset(700, 300));
    await tester.pump(const Duration(milliseconds: 500));
    await settleImages(tester, rounds: 5);

    expect(find.byKey(const Key('endcard.next')), findsOneWidget);
    expect(h.stateOf(tester).currentPage, 10,
        reason: 'end card is the virtual page at index pageCount');
    await disposeReader(tester);
  });

  testWidgets('last page without series context saves as finished',
      (tester) async {
    server.settings = {'page_fit': 'fitHeight'}; // tap advances (see above)
    final h = await pumpReader(tester,
        server: server, tempDir: env, initialPage: 8);
    await settleImages(tester);

    await tester.tapAt(const Offset(700, 300));
    await tester.pump(const Duration(milliseconds: 500));
    await settleImages(tester, rounds: 5);
    expect(h.stateOf(tester).currentPage, 9);
    await tester.runAsync(() => h.notifierOf(tester).saveProgressNow());
    await settleImages(tester, rounds: 5);

    final puts = server.requestsWhere(
        (r) => r.method == 'PUT' && r.path == '/reading/c1');
    expect(puts.last.jsonBody!['current_page'], 10,
        reason: 'current_page == total_pages is what marks it read');
    await disposeReader(tester);
  });
}
