import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/providers/rail_side_provider.dart';
import 'package:comic_reader_app/screens/reader_screen.dart';
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

  // TapZoneOverlay has a 250ms double-tap window; let it fire.
  Future<void> tapAndWait(WidgetTester tester, Offset at) async {
    await tester.tapAt(at);
    await tester.pump(const Duration(milliseconds: 260));
    await tester.pump(const Duration(milliseconds: 350));
  }

  // The test surface is 800 wide, i.e. tablet: the rail is on. Only a
  // swipe up shows it; taps by the rail's edge are ordinary page taps.
  testWidgets('chrome hidden: tap by the rail edge turns the page, no chrome',
      (tester) async {
    // fitHeight: one step per page, so an edge tap turns the page.
    server.settings = {'page_fit': 'fitHeight'};
    final h = await pumpReader(tester, server: server, tempDir: env);
    await settleImages(tester);

    await tapAndWait(tester, const Offset(790, 300));
    await settleImages(tester, rounds: 5);

    expect(h.stateOf(tester).currentPage, 1);
    expect(find.byKey(const Key('reader.back')), findsNothing);
    await disposeReader(tester);
  });

  testWidgets('rail side left: rail moves to the left edge', (tester) async {
    await pumpReader(tester, server: server, tempDir: env);
    await settleImages(tester);
    ProviderScope.containerOf(tester.element(find.byType(ReaderScreen)))
        .read(railSideProvider.notifier)
        .select(RailSide.left);
    tester.state<ReaderScreenState>(find.byType(ReaderScreen)).showChrome();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final more = tester.getRect(find.byKey(const Key('reader.more')));
    expect(more.left, lessThan(ReaderTopBar.railMargin + ReaderTopBar.railWidth));
    await disposeReader(tester);
  });

  testWidgets('phone: far-right tap still pages (no band)', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final h = await pumpReader(tester, server: server, tempDir: env);
    await settleImages(tester);

    await tapAndWait(tester, const Offset(390, 400));
    await settleImages(tester, rounds: 5);

    expect(h.stateOf(tester).currentPage, 1);
    await disposeReader(tester);
  });
}
