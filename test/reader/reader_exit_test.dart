import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/screens/reader_screen.dart';

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

  bool savedProgress() => server
      .requestsWhere((r) => r.method == 'PUT' && r.path.startsWith('/reading/'))
      .isNotEmpty;

  // The reader is the harness's home route, so leaving pops it off and
  // ReaderScreen is gone.
  Future<void> expectLeft(WidgetTester tester) async {
    await settleImages(tester);
    await tester.pump(const Duration(milliseconds: 400));
    expect(savedProgress(), isTrue);
    expect(find.byType(ReaderScreen), findsNothing);
    await disposeReader(tester);
  }

  testWidgets('chrome up: the close beside the title leaves the reader', (tester) async {
    await pumpReader(tester, server: server, tempDir: env);
    await settleImages(tester);
    tester.state<ReaderScreenState>(find.byType(ReaderScreen)).showChrome();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.byKey(const Key('reader.back')));
    await expectLeft(tester);
  });

  testWidgets('a comic with no pages says why and Back leaves', (tester) async {
    await pumpReader(tester, server: server, tempDir: env, comicId: 'missing');
    await settleImages(tester);

    expect(find.text('This comic has no pages.'), findsOneWidget);
    await tester.tap(find.text('Back'));
    await settleImages(tester);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(ReaderScreen), findsNothing);
    await disposeReader(tester);
  });

  testWidgets('a swipe in from the left edge leaves the reader', (tester) async {
    await pumpReader(tester, server: server, tempDir: env);
    await settleImages(tester);

    await tester.dragFrom(const Offset(4, 300), const Offset(200, 0));
    await expectLeft(tester);
  });

  testWidgets('a swipe right from mid-page does not leave', (tester) async {
    await pumpReader(tester, server: server, tempDir: env);
    await settleImages(tester);

    await tester.dragFrom(const Offset(300, 300), const Offset(200, 0));
    await settleImages(tester);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(ReaderScreen), findsOneWidget);
    await disposeReader(tester);
  });

  testWidgets('chrome hidden: no close button on the page', (tester) async {
    await pumpReader(tester, server: server, tempDir: env);
    await settleImages(tester);
    expect(find.byKey(const Key('reader.back')), findsNothing);
    await disposeReader(tester);
  });
}
