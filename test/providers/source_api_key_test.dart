import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:comic_reader_app/models/server_source.dart';
import 'package:comic_reader_app/providers/providers.dart';
import 'package:comic_reader_app/providers/source_provider.dart';

Future<ProviderContainer> _container() async {
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final c = ProviderContainer(
      overrides: [sharedPrefsProvider.overrideWithValue(prefs)]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('updateDefaultApiKey sets Bearer auth on the default source', () async {
    final c = await _container();
    c.read(sourceListProvider.notifier).updateDefaultApiKey('s3cret');
    final src = c.read(activeSourceProvider);
    expect(src.authType, AuthType.apiKey);
    expect(src.authHeaders, {'Authorization': 'Bearer s3cret'});
    expect(src.type, SourceType.custom); // stays the custom backend
  });

  test('empty key clears auth', () async {
    final c = await _container();
    final n = c.read(sourceListProvider.notifier);
    n.updateDefaultApiKey('s3cret');
    n.updateDefaultApiKey('');
    final src = c.read(activeSourceProvider);
    expect(src.authType, AuthType.none);
    expect(src.apiKey, isNull);
    expect(src.authHeaders, isEmpty);
  });

  builtInKeyTests();
}

void builtInKeyTests() {
  tearDown(() => builtInApiKey = '');

  test('fresh install seeds the default source with the built-in key', () async {
    builtInApiKey = 'baked';
    final c = await _container();
    final src = c.read(activeSourceProvider);
    expect(src.authHeaders, {'Authorization': 'Bearer baked'});
  });

  test('no built-in key seeds without auth', () async {
    final c = await _container();
    expect(c.read(activeSourceProvider).authType, AuthType.none);
  });

  Future<ProviderContainer> existingInstall(
      {Map<String, String> secure = const {}}) async {
    var saved = ServerSource.createDefault(url: 'https://my.server');
    if (secure.containsKey('apiKey')) {
      saved = saved.copyWith(authType: AuthType.apiKey); // as _persist saves it
    }
    SharedPreferences.setMockInitialValues({
      'server_sources': jsonEncode([saved.toJson()]),
    });
    FlutterSecureStorage.setMockInitialValues(
        {for (final e in secure.entries) 'source_cred_${saved.id}_${e.key}': e.value});
    final prefs = await SharedPreferences.getInstance();
    final creds = await readSourceCredentials(prefs); // as main() does
    final c = ProviderContainer(overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      sourceCredentialsProvider.overrideWithValue(creds),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  test('stored password is in authHeaders on the first read', () async {
    final saved = ServerSource.createDefault(url: 'https://my.server')
        .copyWith(authType: AuthType.basic, username: 'me');
    SharedPreferences.setMockInitialValues({
      'server_sources': jsonEncode([saved.toJson()]),
    });
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      sourceCredentialsProvider.overrideWithValue(
          {saved.id: (password: 'pw', apiKey: null)}),
    ]);
    addTearDown(c.dispose);
    expect(c.read(activeSourceProvider).authHeaders,
        {'Authorization': 'Basic ${base64Encode(utf8.encode('me:pw'))}'});
  });

  test('existing install with no key picks up the built-in key', () async {
    builtInApiKey = 'baked';
    final c = await existingInstall();
    expect(c.read(activeSourceProvider).authHeaders,
        {'Authorization': 'Bearer baked'});
  });

  test('existing install keeps its own key over the built-in one', () async {
    builtInApiKey = 'baked';
    final c = await existingInstall(secure: {'apiKey': 'mine'});
    expect(c.read(activeSourceProvider).authHeaders,
        {'Authorization': 'Bearer mine'});
  });

  test('existing install without a built-in key stays keyless', () async {
    final c = await existingInstall();
    expect(c.read(activeSourceProvider).authType, AuthType.none);
  });
}
