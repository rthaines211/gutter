import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:comic_reader_app/models/server_source.dart';
import 'package:comic_reader_app/providers/providers.dart';
import 'package:comic_reader_app/providers/source_provider.dart';
import 'package:comic_reader_app/screens/onboarding_screen.dart';

const _secureStorage =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

final _url = find.widgetWithText(TextField, 'Server address');

/// Pumps onboarding; [gutter] picks the Gutter server type first. [probe]
/// sees each candidate URL.
Future<ProviderContainer> _pump(WidgetTester t, Future<bool> Function(String) probe,
    {bool gutter = true, void Function(ServerSource)? onProbe}) async {
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
    child: MaterialApp(
        home: OnboardingScreen(probe: (source) {
      onProbe?.call(source);
      return probe(source.baseUrl);
    })),
  ));
  if (gutter) {
    await t.tap(find.text('Gutter server'));
    await t.pump();
  }
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
    await t.enterText(_url, 'nope.example.com');
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
    await t.enterText(_url, 'comics.example.com/');
    await t.pump(); // enable Connect
    await t.tap(find.text('Connect'));
    await t.pump();
    expect(probed, 'https://comics.example.com');
    expect(c.read(activeSourceProvider).baseUrl, 'https://comics.example.com');
    // Covers and series detail build URLs from ServerConfig, not the source.
    expect(c.read(serverConfigProvider).serverUrl, 'https://comics.example.com');
  });

  test('serverUrlCandidates: no scheme tries https, then http', () {
    expect(serverUrlCandidates('nas.local:8080/'),
        ['https://nas.local:8080', 'http://nas.local:8080']);
    expect(serverUrlCandidates('http://nas.local:8080'), ['http://nas.local:8080']);
  });

  testWidgets('plain-http LAN server typed without a scheme connects',
      (t) async {
    final probed = <String>[];
    final c = await _pump(t, (url) async {
      probed.add(url);
      return url.startsWith('http://');
    });
    await t.enterText(_url, '192.168.1.5:8080');
    await t.pump(); // enable Connect
    await t.tap(find.text('Connect'));
    await t.pump();
    expect(probed, ['https://192.168.1.5:8080', 'http://192.168.1.5:8080']);
    expect(c.read(activeSourceProvider).baseUrl, 'http://192.168.1.5:8080');
  });

  testWidgets('Komga is the default and needs a login', (t) async {
    await _pump(t, (_) async => true, gutter: false);
    await t.enterText(_url, 'komga.example.com');
    await t.pump();
    expect(t.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull,
        reason: 'no username/password yet');
  });

  testWidgets('Komga connect saves a komga source with basic auth', (t) async {
    ServerSource? probed;
    final c = await _pump(t, (_) async => true,
        gutter: false, onProbe: (s) => probed = s);
    await t.enterText(_url, 'https://komga.example.com');
    await t.enterText(find.widgetWithText(TextField, 'Username'), 'reader');
    await t.enterText(find.widgetWithText(TextField, 'Password'), 'pw');
    await t.pump();
    await t.tap(find.text('Connect'));
    await t.pump();
    expect(probed!.type, SourceType.komga);
    expect(probed!.authHeaders['Authorization'], startsWith('Basic '));
    final saved = c.read(activeSourceProvider);
    expect(saved.type, SourceType.komga);
    expect(saved.baseUrl, 'https://komga.example.com');
    expect(saved.username, 'reader');
    expect(saved.password, 'pw');
  });

  testWidgets('Komga with an API key', (t) async {
    final c = await _pump(t, (_) async => true, gutter: false);
    await t.enterText(_url, 'https://komga.example.com');
    await t.tap(find.text('Use an API key'));
    await t.pump();
    await t.enterText(find.widgetWithText(TextField, 'API key'), 'k1');
    await t.pump();
    await t.tap(find.text('Connect'));
    await t.pump();
    expect(c.read(activeSourceProvider).authHeaders, {'X-API-Key': 'k1'});
  });
}
