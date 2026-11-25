import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:comic_reader_app/config/flavor.dart';
import 'package:comic_reader_app/providers/pro_provider.dart';
import 'package:comic_reader_app/providers/settings_provider.dart';

import '../providers/pro_provider_test.dart' show FakeProStore;
import 'fake_comic_server.dart';
import 'harness.dart';

/// A free user gets guided zoom in one issue: the first one opened, with
/// zoom turned on for them (or the first they turn it on in).
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

  testWidgets('first issue opened starts the trial with zoom on', (tester) async {
    server.settings = {'page_fit': 'fitHeight', 'zoom_mode': 'off'};
    final h = await pumpReader(tester,
        server: server,
        tempDir: env,
        extraOverrides: [proStoreProvider.overrideWithValue(FakeProStore())]);
    await settleImages(tester);
    expect(zoomOf(tester, h), 'panels');
    expect((await SharedPreferences.getInstance()).getString(zoomTrialKey), 'c1');
    expect(find.textContaining('free for this issue'), findsOneWidget);
    await disposeReader(tester);
  });

  testWidgets('trial used: zoom stays off, nothing shown', (tester) async {
    server.settings = {'page_fit': 'fitHeight', 'zoom_mode': 'off'};
    final h = await pumpReader(tester,
        server: server,
        tempDir: env,
        extraPrefs: {'zoom_trial_comic': 'another'},
        extraOverrides: [proStoreProvider.overrideWithValue(FakeProStore())]);
    await settleImages(tester);
    expect(zoomOf(tester, h), 'off');
    expect(find.text('Gutter Pro'), findsNothing);
    await disposeReader(tester);
  });

  testWidgets('trial ends: zoom off, and the paywall shows once', (tester) async {
    final h = await pumpReader(tester,
        server: server,
        tempDir: env,
        extraPrefs: {'zoom_trial_comic': 'another'},
        extraOverrides: [proStoreProvider.overrideWithValue(FakeProStore())]);
    await settleImages(tester);
    expect(zoomOf(tester, h), 'off');
    expect(find.text('Gutter Pro'), findsOneWidget);
    expect(find.textContaining('free for one issue'), findsOneWidget);
    await disposeReader(tester);
  });

  testWidgets('trial ended before: only a note', (tester) async {
    final h = await pumpReader(tester,
        server: server,
        tempDir: env,
        extraPrefs: {'zoom_trial_comic': 'another', 'zoom_trial_offer_shown': true},
        extraOverrides: [proStoreProvider.overrideWithValue(FakeProStore())]);
    await settleImages(tester);
    expect(zoomOf(tester, h), 'off');
    expect(find.text('Gutter Pro'), findsNothing);
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
