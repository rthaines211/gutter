import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/models/series.dart';
import 'package:comic_reader_app/widgets/scroll_reader.dart';

import 'fake_comic_server.dart';
import 'harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory env;
  late FakeComicServer server;

  setUpAll(() async => env = await initReaderTestEnv());
  useComicServer(
    () => FakeComicServer()
      ..comics['c1'] = List.filled(12, portraitPage)
      ..settings = {'reading_mode': 'scroll'},
    (s) => server = s,
    () => server,
  );

  testWidgets('scroll mode renders ScrollReader and scrolls through pages',
      (tester) async {
    await pumpReader(tester, server: server, tempDir: env);
    await settleImages(tester);
    expect(find.byType(ScrollReader), findsOneWidget);

    final scrollable = tester.state<ScrollableState>(find.descendant(
        of: find.byType(ScrollReader), matching: find.byType(Scrollable)));
    final before = scrollable.position.pixels;

    await tester.drag(find.byType(ScrollReader), const Offset(0, -2000));
    await settleImages(tester);

    // Scrolling must actually move the viewport, not just survive.
    expect(scrollable.position.pixels, greaterThan(before),
        reason: 'drag must advance scroll offset');
    // ListView must still be alive.
    expect(find.byType(ScrollReader), findsOneWidget);
    await disposeReader(tester);
  });

  testWidgets('scrolling triggers prefetch of upcoming pages', (tester) async {
    await pumpReader(tester, server: server, tempDir: env);
    await settleImages(tester);
    final before = server
        .requestsWhere((r) => r.path.startsWith('/comics/c1/pages/'))
        .length;

    await tester.drag(find.byType(ScrollReader), const Offset(0, -3000));
    await settleImages(tester);

    final after = server
        .requestsWhere((r) => r.path.startsWith('/comics/c1/pages/'))
        .length;
    expect(after, greaterThan(before),
        reason: 'prefetcher must request pages as the viewport moves');
    await disposeReader(tester);
  });

  testWidgets('scrolling advances reading progress', (tester) async {
    final h = await pumpReader(tester, server: server, tempDir: env);
    await settleImages(tester);

    await tester.drag(find.byType(ScrollReader), const Offset(0, -4000));
    await settleImages(tester);

    // onPageChanged wires into goToPage — currentPage must have advanced.
    expect(h.stateOf(tester).currentPage, greaterThan(0));

    // saveProgressNow flushes the debounce and issues the PUT.
    await tester.runAsync(
        () => h.notifierOf(tester).saveProgressNow());
    await settleImages(tester);

    final puts = server.requestsWhere(
        (r) => r.method == 'PUT' && r.path.startsWith('/reading/'));
    expect(puts, isNotEmpty);
    expect(puts.last.jsonBody!['current_page'] as int, greaterThan(0),
        reason: 'scroll progress must reach the server, not just local state');
    await disposeReader(tester);
  });

  testWidgets('scroll mode resumes at saved page', (tester) async {
    // Pump with initialPage: 8 in a 12-page comic.
    final h = await pumpReader(tester,
        server: server, tempDir: env, initialPage: 8);
    await settleImages(tester);

    // The heuristic (offset = initialPage * viewportHeight) is approximate;
    // allow ±1 tolerance for rounding at the floor boundary.
    expect(h.stateOf(tester).currentPage, greaterThanOrEqualTo(7));

    // The fake server must have received a request for page 8 (or nearby),
    // confirming the viewport actually jumped and triggered prefetch/render.
    final pageRequests = server.requestsWhere(
        (r) => r.path.startsWith('/comics/c1/pages/'));
    final requestedIndices = pageRequests
        .map((r) => int.tryParse(r.path.split('/').last) ?? -1)
        .toList();
    expect(requestedIndices.any((i) => i >= 7),
        isTrue,
        reason: 'server should have received requests for pages near 8');
    await disposeReader(tester);
  });

  testWidgets('end card renders after last page when series context exists',
      (tester) async {
    const issues = [
      SeriesIssue(id: 'c1', name: 'Issue 1', coverUrl: '', status: 'reading'),
      SeriesIssue(id: 'c2', name: 'Issue 2', coverUrl: '', status: 'unread'),
    ];
    await pumpReader(tester,
        server: server,
        tempDir: env,
        seriesIssues: issues,
        currentIssueIndex: 0);
    await settleImages(tester);

    // Scroll the ListView to its maximum extent so the end-card virtual item
    // (index pageCount) is built. scrollUntilVisible drives the Scrollable
    // incrementally until the target is in the viewport.
    await tester.scrollUntilVisible(
      find.byKey(const Key('endcard.next')),
      500.0,
      scrollable: find.descendant(
          of: find.byType(ScrollReader), matching: find.byType(Scrollable)),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(const Key('endcard.next')), findsOneWidget,
        reason: 'end card virtual page must render at list end');
    await disposeReader(tester);
  });
}
