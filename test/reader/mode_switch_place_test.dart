import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/providers/settings_provider.dart';
import 'package:comic_reader_app/screens/reader_screen.dart';
import 'package:comic_reader_app/widgets/scroll_reader.dart';

import 'fake_comic_server.dart';
import 'harness.dart';

/// Pages <-> Scroll must keep you on the page you're actually looking at.
/// Pages here are 1000x1500 on an 800x600 view: in scroll mode each page
/// is 1200 tall, two screens, so "one page per screen" maths goes wrong.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory env;
  late FakeComicServer server;

  setUpAll(() async => env = await initReaderTestEnv());
  useComicServer(
    () => FakeComicServer()..comics['c1'] = List.filled(12, portraitPage),
    (s) => server = s,
    () => server,
  );

  /// The page whose image covers the top of the scroll view.
  int pageOnScreen(WidgetTester tester) {
    final top = tester.getRect(find.byType(ScrollReader)).top + 5;
    for (final e in find
        .descendant(
            of: find.byType(ScrollReader),
            matching: find.byType(CachedNetworkImage))
        .evaluate()) {
      final r = tester.getRect(find.byWidget(e.widget));
      if (r.top <= top && r.bottom > top) {
        final url = (e.widget as CachedNetworkImage).imageUrl;
        return int.parse(RegExp(r'pages/(\d+)').firstMatch(url)!.group(1)!);
      }
    }
    fail('no page covers the top of the scroll view');
  }

  Future<void> setMode(WidgetTester tester, String mode) async {
    final c =
        ProviderScope.containerOf(tester.element(find.byType(ReaderScreen)));
    // Not awaited: save() PUTs over real HTTP, which only runs in runAsync.
    c
        .read(settingsProvider.notifier)
        .save(c.read(settingsProvider).value!.copyWith(readingMode: mode));
    await tester.pump();
    for (var i = 0; i < 4; i++) {
      await settleImages(tester, rounds: 10);
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  testWidgets('pages -> scroll lands on the page being read, not the opened one',
      (tester) async {
    server.settings = {'page_fit': 'fitHeight'};
    final h = await pumpReader(tester, server: server, tempDir: env, initialPage: 2);
    await settleImages(tester);
    // Read on from page 2 to page 5.
    for (var i = 0; i < 3; i++) {
      await tester.tapAt(const Offset(700, 300));
      await tester.pump(const Duration(milliseconds: 260));
      await tester.pump(const Duration(milliseconds: 600));
      await settleImages(tester, rounds: 5);
    }
    expect(h.stateOf(tester).currentPage, 5);

    await setMode(tester, 'scroll');
    expect(pageOnScreen(tester), 5);
    expect(h.stateOf(tester).currentPage, 5);
    await disposeReader(tester);
  });

  testWidgets('scroll -> pages lands on the page that was on screen',
      (tester) async {
    server.settings = {'page_fit': 'fitHeight', 'reading_mode': 'scroll'};
    final h = await pumpReader(tester, server: server, tempDir: env);
    for (var i = 0; i < 4; i++) {
      await settleImages(tester, rounds: 10);
      await tester.pump(const Duration(milliseconds: 300));
    }
    // Scroll down a few pages' worth.
    await tester.drag(find.byType(ScrollReader), const Offset(0, -4000));
    for (var i = 0; i < 4; i++) {
      await settleImages(tester, rounds: 10);
      await tester.pump(const Duration(milliseconds: 300));
    }
    final onScreen = pageOnScreen(tester);
    expect(h.stateOf(tester).currentPage, onScreen,
        reason: 'reported page must be the one on screen');

    await setMode(tester, 'page');
    expect(h.stateOf(tester).currentPage, onScreen);
    await disposeReader(tester);
  });
}
