import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/config/flavor.dart';
import 'package:comic_reader_app/providers/pro_provider.dart';
import 'package:comic_reader_app/providers/settings_provider.dart';

import '../providers/pro_provider_test.dart' show FakeProStore;
import 'fake_comic_server.dart';
import 'harness.dart';

/// A free user gets guided zoom in one issue: the first it is turned on in.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory env;
  late FakeComicServer server;

  setUpAll(() async => env = await initReaderTestEnv());
  useComicServer(
    () => FakeComicServer()
      ..comics['c1'] = List.filled(4, portraitPage)
      ..settings = {'page_fit': 'fitHeight', 'zoom_mode': 'panels'},
    (s) => server = s,
    () => server,
  );
  setUp(() => isStore = true);
  tearDown(() => isStore = false);

  String zoomOf(WidgetTester tester, ReaderHarness h) =>
      h.containerOf(tester).read(settingsProvider).value!.zoomMode;

  testWidgets('zoom stays on in the trial issue', (tester) async {
    final h = await pumpReader(tester,
        server: server,
        tempDir: env,
        extraPrefs: {'zoom_trial_comic': 'c1'},
        extraOverrides: [proStoreProvider.overrideWithValue(FakeProStore())]);
    await settleImages(tester);
    expect(zoomOf(tester, h), 'panels');
    await disposeReader(tester);
  });

  testWidgets('zoom turns off in any other issue, with a note', (tester) async {
    final h = await pumpReader(tester,
        server: server,
        tempDir: env,
        extraPrefs: {'zoom_trial_comic': 'another'},
        extraOverrides: [proStoreProvider.overrideWithValue(FakeProStore())]);
    await settleImages(tester);
    expect(zoomOf(tester, h), 'off');
    expect(find.textContaining('free for one issue'), findsOneWidget);
    await disposeReader(tester);
  });

  testWidgets('Pro keeps zoom everywhere', (tester) async {
    final h = await pumpReader(tester,
        server: server,
        tempDir: env,
        extraPrefs: {'zoom_trial_comic': 'another', 'pro_unlocked': true},
        extraOverrides: [proStoreProvider.overrideWithValue(FakeProStore())]);
    await settleImages(tester);
    expect(zoomOf(tester, h), 'panels');
    await disposeReader(tester);
  });
}
