import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:comic_reader_app/models/server_source.dart';
import 'package:comic_reader_app/providers/cache_providers.dart';
import 'package:comic_reader_app/providers/providers.dart';
import 'package:comic_reader_app/providers/server_actions.dart';
import 'package:comic_reader_app/providers/source_provider.dart';
import 'package:comic_reader_app/services/sync_queue.dart';

const _komga = ServerSource(
    id: 'default',
    name: 'Komga',
    type: SourceType.komga,
    baseUrl: 'https://komga.example.com',
    authType: AuthType.basic,
    username: 'me',
    password: 'old',
    isDefault: true);

ServerSource _probed(String url,
        {SourceType type = SourceType.komga, String password = 'new'}) =>
    ServerSource(
        id: 'default',
        name: type == SourceType.komga ? 'Komga' : 'My Server',
        type: type,
        baseUrl: url,
        authType: AuthType.basic,
        username: 'me',
        password: password,
        isDefault: true);

late Directory docs;

/// A container whose saved sources are [sources] (first active), with docs
/// in a temp dir and every source's mirror file on disk.
Future<ProviderContainer> _container(List<ServerSource> sources) async {
  SharedPreferences.setMockInitialValues({
    'server_sources': jsonEncode(sources.map((s) => s.toJson()).toList()),
    'active_source_id': sources.first.id,
  });
  FlutterSecureStorage.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final c = ProviderContainer(overrides: [
    sharedPrefsProvider.overrideWithValue(prefs),
    docsDirProvider.overrideWith((_) async => docs.path),
  ]);
  addTearDown(c.dispose);
  for (final s in sources) {
    File(_mirror(s.id)).createSync();
  }
  return c;
}

String _mirror(String id) => p.join(docs.path, 'mirror_$id.sqlite');

List<ServerSource> _sources(ProviderContainer c) => c.read(sourceListProvider);
ServerSource _active(ProviderContainer c) => c.read(activeSourceProvider);
ServerActions _actions(ProviderContainer c) => c.read(serverActionsProvider);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async => docs = await Directory.systemTemp.createTemp('srvact_'));
  tearDown(() => docs.delete(recursive: true));

  test('same server keeps id and data', () async {
    final c = await _container([_komga]);
    await _actions(c).save(old: _komga, found: _probed(_komga.baseUrl));
    expect(_sources(c).single.id, 'default');
    expect(_sources(c).single.password, 'new');
    expect(File(_mirror('default')).existsSync(), isTrue);
  });

  test('trailing slash is the same server', () async {
    expect(sameServer(_komga, _probed('https://komga.example.com/')), isTrue);
    expect(sameServer(_komga, _probed('komga.example.com')), isTrue);
    expect(
        sameServer(_komga,
            _probed(_komga.baseUrl, type: SourceType.custom)),
        isFalse);
  });

  test('new address gets new id, is selected, old files deleted, '
      'isDefault carried', () async {
    final c = await _container([_komga]);
    await _actions(c).save(old: _komga, found: _probed('https://other.example'));
    final s = _sources(c).single;
    expect(s.id, isNot('default'));
    expect(s.baseUrl, 'https://other.example');
    expect(s.isDefault, isTrue);
    expect(_active(c).id, s.id);
    expect(File(_mirror('default')).existsSync(), isFalse);
  });

  test('editing an inactive server to a new address keeps the active one',
      () async {
    const two = ServerSource(
        id: 'two',
        name: 'Two',
        type: SourceType.komga,
        baseUrl: 'https://two.example',
        authType: AuthType.none);
    final c = await _container([_komga, two]);
    await _actions(c).save(old: two, found: _probed('https://three.example'));
    expect(_active(c).id, 'default');
    expect(_sources(c).map((s) => s.baseUrl),
        [_komga.baseUrl, 'https://three.example']);
    expect(File(_mirror('two')).existsSync(), isFalse);
  });

  test('add selects the new server, isDefault false', () async {
    final c = await _container([_komga]);
    await _actions(c).save(found: _probed('https://two.example'));
    expect(_sources(c), hasLength(2));
    expect(_active(c).baseUrl, 'https://two.example');
    expect(_active(c).isDefault, isFalse);
    expect(_sources(c).first.isDefault, isTrue);
  });

  test('sign out of last server leaves a blank default with a new id',
      () async {
    final c = await _container([_komga]);
    await _actions(c).signOut(_komga);
    final s = _sources(c).single;
    expect(s.baseUrl, '');
    expect(s.id, isNot('default'));
    expect(s.isDefault, isTrue);
    expect(_active(c).id, s.id);
    expect(File(_mirror('default')).existsSync(), isFalse);
  });

  test('sign out of active default with others: next becomes active + default',
      () async {
    const two = ServerSource(
        id: 'two',
        name: 'Two',
        type: SourceType.custom,
        baseUrl: 'https://two.example',
        authType: AuthType.none);
    final c = await _container([_komga, two]);
    await _actions(c).signOut(_komga);
    expect(_sources(c).single.id, 'two');
    expect(_active(c).id, 'two');
    expect(_active(c).isDefault, isTrue);
  });

  test('forget with no files on disk still removes the source', () async {
    final c = await _container([_komga]);
    File(_mirror('default')).deleteSync();
    await _actions(c).signOut(_komga);
    expect(_sources(c).any((s) => s.id == 'default'), isFalse);
  });

  test('flushOutbox returns what the drain left', () async {
    final c = await _container([_komga]);
    final queue = SyncQueue(
        queuePath: p.join(docs.path, 'cache', 'default', 'sync_queue.json'));
    await queue.enqueue({'type': 'progress', 'payload': {}});
    await queue.enqueue({'type': 'progress', 'payload': {}});
    final actions = _actions(c)..drain = (s, q) => q.removeFirst();
    expect(await actions.pendingCount(_komga), 2);
    expect(await actions.flushOutbox(_komga), 1);
  });

  test('builtInApiKey does not overwrite a basic-auth default', () async {
    builtInApiKey = 'built-in';
    addTearDown(() => builtInApiKey = '');
    const gutter = ServerSource(
        id: 'default',
        name: 'My Server',
        type: SourceType.custom,
        baseUrl: 'https://g.example',
        authType: AuthType.basic,
        username: 'u',
        isDefault: true);
    final c = await _container([gutter]);
    expect(_active(c).authType, AuthType.basic);
  });
}
