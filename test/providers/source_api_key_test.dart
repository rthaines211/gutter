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
}
