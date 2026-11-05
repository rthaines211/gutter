import 'dart:convert';

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

Future<ProviderContainer> _pump(
    WidgetTester t, Future<int?> Function(String, Map<String, String>) probe) async {
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
    final c = await _pump(t, (_, _) async => null);
    await t.enterText(find.byType(TextField), 'nope.example.com');
    await t.pump(); // enable Connect
    await t.tap(find.text('Connect'));
    await t.pump();
    expect(find.textContaining("Couldn't reach"), findsOneWidget);
    expect(c.read(activeSourceProvider).baseUrl, isEmpty);
  });

  testWidgets('reachable server: saved as the default source', (t) async {
    String? probed;
    final c = await _pump(t, (url, _) async {
      probed = url;
      return 200;
    });
    await t.enterText(find.byType(TextField), 'comics.example.com/');
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
    final c = await _pump(t, (url, _) async {
      probed.add(url);
      return url.startsWith('http://') ? 200 : null;
    });
    await t.enterText(find.byType(TextField), '192.168.1.5:8080');
    await t.pump(); // enable Connect
    await t.tap(find.text('Connect'));
    await t.pump();
    expect(probed, ['https://192.168.1.5:8080', 'http://192.168.1.5:8080']);
    expect(c.read(activeSourceProvider).baseUrl, 'http://192.168.1.5:8080');
  });

  testWidgets('200 connects without asking for credentials', (t) async {
    await _pump(t, (_, _) async => 200);
    await t.enterText(find.byType(TextField), 'comics.example.com');
    await t.pump();
    await t.tap(find.text('Connect'));
    await t.pump();
    expect(find.text('Password'), findsNothing);
  });

  final basic = 'Basic ${base64Encode(utf8.encode('me:pw'))}';
  Future<int?> authed(String url, Map<String, String> h) async =>
      h['Authorization'] == basic ? 200 : 401;

  Future<void> typeUrlAndConnect(WidgetTester t) async {
    await t.enterText(find.byType(TextField), 'comics.example.com');
    await t.pump();
    await t.tap(find.text('Connect'));
    await t.pump();
  }

  testWidgets('401 reveals username + password fields, then connects with Basic',
      (t) async {
    final probed = <String>[];
    final c = await _pump(t, (u, h) {
      probed.add(u);
      return authed(u, h);
    });
    await typeUrlAndConnect(t);
    expect(find.textContaining('needs a password'), findsOneWidget);
    expect(probed, ['https://comics.example.com']); // http not tried
    expect(c.read(activeSourceProvider).baseUrl, isEmpty);
    await t.enterText(find.widgetWithText(TextField, 'Username'), 'me');
    await t.enterText(find.widgetWithText(TextField, 'Password'), 'pw');
    await t.pump();
    await t.tap(find.text('Connect'));
    await t.pump();
    final s = c.read(activeSourceProvider);
    expect(s.authType, AuthType.basic);
    expect(s.username, 'me');
    expect(s.password, 'pw');
    expect(s.baseUrl, 'https://comics.example.com');
  });

  testWidgets('401 again shows "Wrong username or password"', (t) async {
    final c = await _pump(t, (_, _) async => 401);
    await typeUrlAndConnect(t);
    await t.enterText(find.widgetWithText(TextField, 'Username'), 'me');
    await t.enterText(find.widgetWithText(TextField, 'Password'), 'bad');
    await t.pump();
    await t.tap(find.text('Connect'));
    await t.pump();
    expect(find.text('Wrong username or password'), findsOneWidget);
    expect(c.read(activeSourceProvider).baseUrl, isEmpty);
  });
}
