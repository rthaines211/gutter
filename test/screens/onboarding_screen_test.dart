import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:comic_reader_app/providers/providers.dart';
import 'package:comic_reader_app/providers/source_provider.dart';
import 'package:comic_reader_app/screens/onboarding_screen.dart';

const _secureStorage =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

Future<ProviderContainer> _pump(
    WidgetTester t, Future<bool> Function(String) probe) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  // No plugin implementation under flutter_test.
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_secureStorage,
          (call) async => call.method == 'readAll' ? <String, String>{} : null);
  addTearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_secureStorage, null));
  final container = ProviderContainer(
      overrides: [sharedPrefsProvider.overrideWithValue(prefs)]);
  addTearDown(container.dispose);
  await t.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(home: OnboardingScreen(probe: probe)),
  ));
  return container;
}

void main() {
  test('normalizeServerUrl', () {
    expect(normalizeServerUrl(' comics.example.com/ '),
        'https://comics.example.com');
    expect(normalizeServerUrl('192.168.1.5:8080'), 'https://192.168.1.5:8080');
    expect(normalizeServerUrl('http://nas.local:8080/'), 'http://nas.local:8080');
    expect(normalizeServerUrl('https://x.example.com/api//'),
        'https://x.example.com/api');
  });

  testWidgets('unreachable server: error shown, URL not saved', (t) async {
    final c = await _pump(t, (_) async => false);
    await t.enterText(find.byType(TextField), 'nope.example.com');
    await t.pump(); // enable Connect
    await t.tap(find.text('Connect'));
    await t.pump();
    expect(find.textContaining("Couldn't reach"), findsOneWidget);
    expect(c.read(activeSourceProvider).baseUrl, isEmpty);
  });

  testWidgets('reachable server: saved as the default source', (t) async {
    String? probed;
    final c = await _pump(t, (url) async {
      probed = url;
      return true;
    });
    await t.enterText(find.byType(TextField), 'comics.example.com/');
    await t.pump(); // enable Connect
    await t.tap(find.text('Connect'));
    await t.pump();
    expect(probed, 'https://comics.example.com');
    expect(c.read(activeSourceProvider).baseUrl, 'https://comics.example.com');
  });
}
