import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/config/flavor.dart';
import 'package:comic_reader_app/providers/pro_provider.dart';
import 'package:comic_reader_app/providers/providers.dart';
import 'package:comic_reader_app/screens/reader_screen.dart';

import 'fake_comic_server.dart';
import 'harness.dart';
import '../providers/pro_provider_test.dart' show FakeProStore;

/// Reader features that need a Gutter server (panel/balloon data, chapter
/// detection, credits) stay off Komga; the labeller stays off store builds.
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

  Future<void> open(WidgetTester tester, {required bool gutter}) async {
    server.settings = {...server.settings, 'page_fit': 'fitHeight'};
    await pumpReader(tester,
        server: server,
        tempDir: env,
        extraOverrides: [
          isCustomSourceProvider.overrideWithValue(gutter),
          proStoreProvider.overrideWithValue(FakeProStore()),
        ]);
    await settleImages(tester);
  }

  Future<void> openMore(WidgetTester tester) async {
    tester.state<ReaderScreenState>(find.byType(ReaderScreen)).showChrome();
    await tester.pump(const Duration(milliseconds: 260));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.tap(find.bySemanticsLabel('More'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('Komga: More has no Chapters, Clip a panel or Credits',
      (tester) async {
    await open(tester, gutter: false);
    await openMore(tester);
    expect(find.text('All pages'), findsOneWidget);
    expect(find.text('Chapters'), findsNothing);
    expect(find.text('Clip a panel'), findsNothing);
    expect(find.text('Credits'), findsNothing);
    await disposeReader(tester);
  });

  testWidgets('Komga: no balloon requests and long-press offers no clip',
      (tester) async {
    await open(tester, gutter: false);
    final g = await tester.startGesture(const Offset(400, 300));
    await tester.pump(const Duration(milliseconds: 600));
    await g.up();
    await settleImages(tester);
    expect(server.requestsWhere((r) => r.path.contains('/bubbles')), isEmpty);
    expect(find.textContaining('panel'), findsNothing);
    await disposeReader(tester);
  });

  testWidgets('Gutter server: More keeps Chapters, Clip a panel and Credits',
      (tester) async {
    await open(tester, gutter: true);
    await openMore(tester);
    expect(find.text('Chapters'), findsOneWidget);
    expect(find.text('Clip a panel'), findsOneWidget);
    expect(find.text('Credits'), findsOneWidget);
    await disposeReader(tester);
  });

  testWidgets('store build: no Fix panels or Fix balloons', (tester) async {
    isStore = true;
    addTearDown(() => isStore = false);
    await open(tester, gutter: true);
    await openMore(tester);
    expect(find.text('All pages'), findsOneWidget);
    expect(find.text('Fix panels'), findsNothing);
    expect(find.text('Fix balloons'), findsNothing);
    await disposeReader(tester);
  });
}
