import 'dart:convert';


import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:comic_reader_app/config/flavor.dart';
import 'package:comic_reader_app/config/platform.dart';
import 'package:comic_reader_app/models/server_source.dart';
import 'package:comic_reader_app/providers/server_actions.dart';
import 'package:comic_reader_app/providers/providers.dart';
import 'package:comic_reader_app/providers/source_provider.dart';
import 'package:comic_reader_app/screens/onboarding_screen.dart';

const _secureStorage =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

final _url = find.widgetWithText(TextField, 'Server address');

/// Pumps onboarding; [gutter] picks the Gutter server type first. [probe]
/// sees each candidate URL.
Future<ProviderContainer> _pump(
    WidgetTester t, Future<int?> Function(String, Map<String, String>) probe,
    {bool gutter = true,
    void Function(ServerSource)? onProbe,
    ServerSource? initial,
    Future<String?> Function(ServerSource)? kavitaLogin,
    Future<void> Function(ServerSource)? onConnected}) async {
  // Tall enough that Connect is on screen with four server types (the
  // segment labels wrap in the test font).
  t.view.physicalSize = const Size(800, 800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
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
        home: OnboardingScreen(
            initial: initial,
            onConnected: onConnected,
            kavitaLogin: kavitaLogin,
            probe: (source) {
              onProbe?.call(source);
              return probe(source.baseUrl, source.authHeaders);
            })),
  ));
  if (gutter && initial == null) {
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
    final c = await _pump(t, (_, _) async => null);
    await t.enterText(_url, 'nope.example.com');
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
    final c = await _pump(t, (url, _) async {
      probed.add(url);
      return url.startsWith('http://') ? 200 : null;
    });
    await t.enterText(_url, '192.168.1.5:8080');
    await t.pump(); // enable Connect
    await t.tap(find.text('Connect'));
    await t.pump();
    expect(probed, ['https://192.168.1.5:8080', 'http://192.168.1.5:8080']);
    expect(c.read(activeSourceProvider).baseUrl, 'http://192.168.1.5:8080');
  });

  testWidgets('Komga is the default and needs a login', (t) async {
    await _pump(t, (_, _) async => 200, gutter: false);
    await t.enterText(_url, 'komga.example.com');
    await t.pump();
    expect(t.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull,
        reason: 'no username/password yet');
  });

  testWidgets('Komga connect saves a komga source with basic auth', (t) async {
    ServerSource? probed;
    final c = await _pump(t, (_, _) async => 200,
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
    final c = await _pump(t, (_, _) async => 200, gutter: false);
    await t.enterText(_url, 'https://komga.example.com');
    await t.tap(find.text('Use an API key'));
    await t.pump();
    await t.enterText(find.widgetWithText(TextField, 'API key'), 'k1');
    await t.pump();
    await t.tap(find.text('Connect'));
    await t.pump();
    expect(c.read(activeSourceProvider).authHeaders, {'X-API-Key': 'k1'});
  });

  testWidgets('Komga login never falls back to plain http on its own', (t) async {
    final probed = <String>[];
    await _pump(t, (url, _) async {
      probed.add(url);
      return null;
    }, gutter: false);
    await t.enterText(_url, 'komga.example.com');
    await t.enterText(find.widgetWithText(TextField, 'Username'), 'reader');
    await t.enterText(find.widgetWithText(TextField, 'Password'), 'pw');
    await t.pump();
    await t.tap(find.text('Connect'));
    await t.pump();
    expect(probed, ['https://komga.example.com']);
  });

  testWidgets('Kavita login is traded for the auth key, which is saved',
      (t) async {
    ServerSource? loggedIn, probed;
    final c = await _pump(t, (_, _) async => 200,
        gutter: false,
        onProbe: (s) => probed = s,
        kavitaLogin: (s) async {
          loggedIn = s;
          return 'ak';
        });
    await t.tap(find.text('Kavita'));
    await t.pump();
    await t.enterText(_url, 'https://kavita.example.com');
    await t.enterText(find.widgetWithText(TextField, 'Username'), 'reader');
    await t.enterText(find.widgetWithText(TextField, 'Password'), 'pw');
    await t.pump();
    await t.tap(find.text('Connect'));
    await t.pump();
    expect(loggedIn!.username, 'reader');
    expect(loggedIn!.password, 'pw');
    expect(probed!.authHeaders, {'X-API-Key': 'ak'});
    final saved = c.read(activeSourceProvider);
    expect(saved.type, SourceType.kavita);
    expect(saved.name, 'Kavita');
    expect(saved.authType, AuthType.apiKey);
    expect(saved.password, isNull);
  });

  testWidgets('Kavita refused login shows an error and probes nothing',
      (t) async {
    var probes = 0;
    final c = await _pump(t, (_, _) async => 200,
        gutter: false,
        onProbe: (_) => probes++,
        kavitaLogin: (_) async => null);
    await t.tap(find.text('Kavita'));
    await t.pump();
    await t.enterText(_url, 'kavita.example.com');
    await t.enterText(find.widgetWithText(TextField, 'Username'), 'reader');
    await t.enterText(find.widgetWithText(TextField, 'Password'), 'bad');
    await t.pump();
    await t.tap(find.text('Connect'));
    await t.pump();
    expect(probes, 0);
    expect(find.textContaining("Couldn't sign in to Kavita"), findsOneWidget);
    expect(c.read(activeSourceProvider).baseUrl, isEmpty);
  });

  testWidgets('Kavita with an auth key skips the login', (t) async {
    var logins = 0;
    final c = await _pump(t, (_, _) async => 200,
        gutter: false, kavitaLogin: (_) async {
      logins++;
      return null;
    });
    await t.tap(find.text('Kavita'));
    await t.pump();
    await t.enterText(_url, 'https://kavita.example.com');
    await t.tap(find.text('Use an API key'));
    await t.pump();
    await t.enterText(find.widgetWithText(TextField, 'API key'), 'k1');
    await t.pump();
    await t.tap(find.text('Connect'));
    await t.pump();
    expect(logins, 0);
    expect(c.read(activeSourceProvider).authHeaders, {'X-API-Key': 'k1'});
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

  testWidgets('editing the URL after a 401 probes the new address', (t) async {
    final probed = <String>[];
    final c = await _pump(t, (u, h) async {
      probed.add(u);
      return u.contains('a.example.com') ? 401 : 200;
    });
    await t.enterText(find.byType(TextField), 'a.example.com');
    await t.pump();
    await t.tap(find.text('Connect'));
    await t.pump();
    expect(find.text('Password'), findsOneWidget);
    await t.enterText(
        find.widgetWithText(TextField, 'Server address'), 'b.example.com');
    await t.pump();
    expect(find.text('Password'), findsNothing);
    expect(find.textContaining('needs a password'), findsNothing);
    await t.tap(find.text('Connect'));
    await t.pump();
    expect(probed.last, 'https://b.example.com');
    expect(c.read(activeSourceProvider).baseUrl, 'https://b.example.com');
  });

  testWidgets('first probe sends the default source\'s existing auth',
      (t) async {
    builtInApiKey = 'baked';
    addTearDown(() => builtInApiKey = '');
    final c = await _pump(t, (_, h) async =>
        h['Authorization'] == 'Bearer baked' ? 200 : 401);
    await typeUrlAndConnect(t);
    expect(find.text('Password'), findsNothing);
    final s = c.read(activeSourceProvider);
    expect(s.baseUrl, 'https://comics.example.com');
    expect(s.authHeaders, {'Authorization': 'Bearer baked'});
  });

  testWidgets('username field explains any name works', (t) async {
    await _pump(t, (_, _) async => 401);
    await typeUrlAndConnect(t);
    expect(find.text('Any name works for Gutter Server'), findsOneWidget);
  });

  group('OPDS', () {
    Future<ProviderContainer> pumpOpds(WidgetTester t,
        {void Function(ServerSource)? onProbe, int? status = 200}) async {
      final c = await _pump(t, (_, _) async => status,
          gutter: false, onProbe: onProbe);
      await t.tap(find.text('OPDS'));
      await t.pump();
      return c;
    }

    testWidgets('a catalog URL connects without a login and is saved as an '
        'OPDS source: origin + catalog path', (t) async {
      ServerSource? probed;
      final c = await pumpOpds(t, onProbe: (s) => probed = s);
      expect(find.text('Use an API key'), findsNothing);
      await t.enterText(_url, 'kavita.example.com/api/opds/abc123/');
      await t.pump();
      await t.tap(find.text('Connect'));
      await t.pump();
      expect(probed!.type, SourceType.opds);
      expect(probed!.baseUrl, 'https://kavita.example.com');
      expect(probed!.catalogPath, '/api/opds/abc123');
      expect(probed!.authHeaders, isEmpty);
      final saved = c.read(activeSourceProvider);
      expect(saved.type, SourceType.opds);
      expect(saved.name, 'OPDS');
      expect(saved.address, 'https://kavita.example.com/api/opds/abc123');
      expect(c.read(apiClientProvider).baseUrl, 'https://kavita.example.com');
      // Not a Gutter server: no server-only features.
      expect(c.read(isCustomSourceProvider), isFalse);
      expect(c.read(gutterFeaturesProvider), isFalse);
    });

    testWidgets('a username and password become Basic auth', (t) async {
      ServerSource? probed;
      await pumpOpds(t, onProbe: (s) => probed = s);
      await t.enterText(_url, 'https://komga.example.com/opds/v1.2/catalog');
      await t.enterText(find.widgetWithText(TextField, 'Username'), 'reader');
      await t.enterText(find.widgetWithText(TextField, 'Password'), 'pw');
      await t.pump();
      await t.tap(find.text('Connect'));
      await t.pump();
      expect(probed!.authHeaders['Authorization'],
          'Basic ${base64Encode(utf8.encode('reader:pw'))}');
      expect(probed!.catalogPath, '/opds/v1.2/catalog');
    });

    testWidgets('a page that is not a feed says to use the catalog address',
        (t) async {
      final c = await pumpOpds(t, status: null);
      await t.enterText(_url, 'comics.example.com');
      await t.pump();
      await t.tap(find.text('Connect'));
      await t.pump();
      expect(find.textContaining('OPDS catalog address'), findsOneWidget);
      expect(c.read(activeSourceProvider).baseUrl, isEmpty);
    });

    testWidgets('edit mode prefills the whole catalog address', (t) async {
      await _pump(t, (_, _) async => 200,
          initial: const ServerSource(
              id: 'o',
              name: 'OPDS',
              type: SourceType.opds,
              baseUrl: 'https://komga.example.com',
              catalogPath: '/opds/v1.2/catalog',
              authType: AuthType.none),
          onConnected: (_) async {});
      expect(find.text('https://komga.example.com/opds/v1.2/catalog'),
          findsOneWidget);
    });
  });

  group('edit / add mode', () {
    const komga = ServerSource(
        id: 'k',
        name: 'Komga',
        type: SourceType.komga,
        baseUrl: 'https://komga.example.com',
        authType: AuthType.basic,
        username: 'reader',
        password: 'old');

    testWidgets('edit mode prefills Komga login', (t) async {
      await _pump(t, (_, _) async => 200,
          initial: komga, onConnected: (_) async {});
      expect(find.text('Edit server'), findsOneWidget);
      expect(find.text('https://komga.example.com'), findsOneWidget);
      expect(find.text('reader'), findsOneWidget);
      expect(t.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNotNull);
    });

    testWidgets('edit mode shows Gutter login fields for a basic-auth source',
        (t) async {
      const gutter = ServerSource(
          id: 'g',
          name: 'My Server',
          type: SourceType.custom,
          baseUrl: 'https://comics.example.com',
          authType: AuthType.basic,
          username: 'me',
          password: 'pw');
      await _pump(t, (_, _) async => 200,
          initial: gutter, onConnected: (_) async {});
      expect(find.widgetWithText(TextField, 'Username'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Password'), findsOneWidget);
    });

    testWidgets('onConnected receives the probed source; default source '
        'untouched', (t) async {
      ServerSource? got;
      final c = await _pump(t, (_, _) async => 200,
          initial: komga, onConnected: (s) async => got = s);
      final before = c.read(sourceListProvider);
      await t.enterText(find.widgetWithText(TextField, 'Password'), 'new');
      await t.pump();
      await t.ensureVisible(find.text('Connect'));
      await t.tap(find.text('Connect'));
      await t.pump();
      expect(got!.password, 'new');
      expect(got!.type, SourceType.komga);
      expect(c.read(sourceListProvider), same(before));
    });

    testWidgets('add mode is titled Add server', (t) async {
      await _pump(t, (_, _) async => 200,
          gutter: false, onConnected: (_) async {});
      expect(find.text('Add server'), findsOneWidget);
    });
  });

  group('read files on this device', () {
    final action = find.text('Import comics from Files');

    for (final store in [true, false]) {
      testWidgets('sets up the local source (store: $store)', (t) async {
        isStore = store;
        addTearDown(() => isStore = false);
        final c = await _pump(t, (_, _) async => null, gutter: false);
        final blankId = c.read(activeSourceProvider).id;
        expect(c.read(activeSourceProvider).baseUrl, isEmpty);

        expect(action, findsOneWidget);
        // Once a file is picked, the import calls this.
        c.read(serverActionsProvider).useLocal();
        await t.pump();

        final s = c.read(activeSourceProvider);
        expect(s.type, SourceType.local);
        // Not empty, so the app leaves onboarding; same id, still default.
        expect(s.baseUrl, isNotEmpty);
        expect((s.id, s.isDefault), (blankId, true));
        expect(c.read(sourceListProvider).length, 1);
      });
    }

    testWidgets('not offered on Android', (t) async {
      isAndroid = true;
      addTearDown(() => isAndroid = false);
      await _pump(t, (_, _) async => null, gutter: false);
      expect(action, findsNothing);
    });

    testWidgets('not in the Servers add/edit form', (t) async {
      await _pump(t, (_, _) async => null,
          gutter: false, onConnected: (_) async {});
      expect(action, findsNothing);
    });
  });
}
