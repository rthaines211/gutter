import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/providers/settings_provider.dart';
import 'package:comic_reader_app/screens/reader_screen.dart';

import 'fake_comic_server.dart';
import 'harness.dart';

/// Changing a reader setting mid-page must keep your place on the page,
/// not snap back to its first step.
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

  Matrix4 transform(WidgetTester tester) => tester
      .widget<InteractiveViewer>(find.byType(InteractiveViewer).first)
      .transformationController!
      .value;

  testWidgets('fit change mid-page keeps the lower part of the page in view',
      (tester) async {
    final h = await pumpReader(tester, server: server, tempDir: env, initialPage: 4);
    await settleImages(tester);
    // fitScreen on 800x600 zooms a portrait page: one right tap = bottom step.
    await tester.tapAt(const Offset(700, 300));
    await tester.pump(const Duration(milliseconds: 260));
    await tester.pump(const Duration(milliseconds: 600));
    await settleImages(tester, rounds: 5);
    expect(transform(tester).getTranslation().y, lessThan(-100),
        reason: 'precondition: looking at the lower part of the page');

    final c = ProviderScope.containerOf(tester.element(find.byType(ReaderScreen)));
    // Not awaited: save() PUTs over real HTTP, which only runs in runAsync.
    c.read(settingsProvider.notifier)
        .save(c.read(settingsProvider).value!.copyWith(pageFit: 'fitWidth'));
    await tester.pump();
    await settleImages(tester, rounds: 10);
    await tester.pump(const Duration(milliseconds: 500));

    expect(h.stateOf(tester).currentPage, 4);
    expect(transform(tester).getTranslation().y, lessThan(-100),
        reason: 'still on the lower part of the page, not back at the top');
    await disposeReader(tester);
  });
}
