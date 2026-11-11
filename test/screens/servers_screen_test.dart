import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:comic_reader_app/config/flavor.dart';
import 'package:comic_reader_app/config/platform.dart';
import 'package:comic_reader_app/providers/download_provider.dart';
import 'package:comic_reader_app/services/download_manager.dart';
import 'package:comic_reader_app/models/server_source.dart';
import 'package:comic_reader_app/providers/cache_providers.dart';
import 'package:comic_reader_app/providers/connectivity_provider.dart';
import 'package:comic_reader_app/providers/pro_provider.dart';
import 'package:comic_reader_app/providers/providers.dart';
import 'package:comic_reader_app/providers/server_actions.dart';
import 'package:comic_reader_app/providers/source_provider.dart';
import 'package:comic_reader_app/screens/servers_screen.dart';
import 'package:comic_reader_app/widgets/pro_sheet.dart';

import '../providers/pro_provider_test.dart' show FakeProStore;

const _one = ServerSource(
    id: 'one',
    name: 'My Server',
    type: SourceType.custom,
    baseUrl: 'https://one.example',
    authType: AuthType.none,
    isDefault: true);
const _two = ServerSource(
    id: 'two',
    name: 'Komga',
    type: SourceType.komga,
    baseUrl: 'https://two.example',
    authType: AuthType.none);

late Directory docs;

class _Connectivity extends ConnectivityNotifier {
  _Connectivity(this.online);
  final bool online;
  @override
  bool build() => online;
}

var drains = 0;

Future<ProviderContainer> _pump(WidgetTester t, List<ServerSource> sources,
    {bool online = true, bool noDownloads = false}) async {
  SharedPreferences.setMockInitialValues({
    'server_sources': jsonEncode(sources.map((s) => s.toJson()).toList()),
    'active_source_id': sources.first.id,
  });
  FlutterSecureStorage.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final c = ProviderContainer(overrides: [
    sharedPrefsProvider.overrideWithValue(prefs),
    proStoreProvider.overrideWithValue(FakeProStore()),
    docsDirProvider.overrideWith((_) async => docs.path),
    connectivityProvider.overrideWith(() => _Connectivity(online)),
    if (noDownloads) downloadManagerProvider.overrideWithValue(null),
  ]);
  addTearDown(c.dispose);
  // The server rejects everything: the drain sends nothing.
  drains = 0;
  c.read(serverActionsProvider).drain = (_, _) async => drains++;
  await t.pumpWidget(UncontrolledProviderScope(
      container: c, child: const MaterialApp(home: ServersScreen())));
  await t.pump();
  return c;
}

File _queueFile(String id) =>
    File(p.join(docs.path, 'cache', id, 'sync_queue.json'));

Future<void> _signOut(WidgetTester t, String name) async {
  await t.tap(find.byTooltip('$name options'));
  await t.pumpAndSettle();
  await t.tap(find.text('Sign out'));
  await t.pumpAndSettle();
  // Confirm dialog's action.
  await t.tap(find.widgetWithText(TextButton, 'Sign out'));
  await _settle(t);
}

/// File I/O only completes on the real event loop: alternate real waits
/// with pumps until the chain of reads and writes is through.
Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 10; i++) {
    await t.runAsync(() => Future.delayed(const Duration(milliseconds: 20)));
    await t.pump();
  }
  await t.pumpAndSettle();
}

void main() {
  setUp(() async => docs = await Directory.systemTemp.createTemp('servers_'));
  tearDown(() => docs.delete(recursive: true));

  testWidgets('store build without Pro: Add server opens the Pro sheet',
      (t) async {
    isStore = true;
    addTearDown(() => isStore = false);
    await _pump(t, [_one]);
    await t.tap(find.text('Add server'));
    await t.pumpAndSettle();
    expect(find.byType(ProSheet), findsOneWidget);
  });

  testWidgets('sign out with pending changes shows the dialog; Cancel keeps '
      'the server', (t) async {
    _queueFile('one')
      ..createSync(recursive: true)
      ..writeAsStringSync(jsonEncode([
        {'type': 'progress', 'payload': {}},
        {'type': 'progress', 'payload': {}},
      ]));
    final c = await _pump(t, [_one]);
    await _signOut(t, 'My Server');
    expect(find.text('2 changes not synced to My Server'), findsOneWidget);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(c.read(sourceListProvider).single.id, 'one');
    expect(jsonDecode(_queueFile('one').readAsStringSync()), hasLength(2));
  });

  testWidgets('Discard and continue signs out', (t) async {
    _queueFile('one')
      ..createSync(recursive: true)
      ..writeAsStringSync(jsonEncode([
        {'type': 'progress', 'payload': {}},
      ]));
    final c = await _pump(t, [_one]);
    await _signOut(t, 'My Server');
    await t.tap(find.text('Discard and continue'));
    await _settle(t);
    final s = c.read(sourceListProvider).single;
    expect(s.id, isNot('one'));
    expect(s.baseUrl, '');
    expect(_queueFile('one').existsSync(), isFalse);
  });

  testWidgets('offline: no drain attempt, pending dialog at once', (t) async {
    _queueFile('one')
      ..createSync(recursive: true)
      ..writeAsStringSync(jsonEncode([
        {'type': 'progress', 'payload': {}},
      ]));
    await _pump(t, [_one], online: false);
    await _signOut(t, 'My Server');
    expect(find.text('1 change not synced to My Server'), findsOneWidget);
    expect(drains, 0);
  });

  testWidgets('tap switches the active server', (t) async {
    final c = await _pump(t, [_one, _two]);
    await t.tap(find.text('Komga'));
    await t.pump();
    expect(c.read(activeSourceIdProvider), 'two');
  });

  group('local source', () {
    const local = ServerSource.local(id: 'loc');
    final add = find.text('Import comics from Files');

    testWidgets('adding it is free and needs no Pro, next to a server',
        (t) async {
      isStore = true;
      addTearDown(() => isStore = false);
      final c = await _pump(t, [_one], noDownloads: true);
      // No picker under test: the tap is free (no Pro sheet), and with no
      // file picked no source is made.
      await t.tap(add);
      await t.pumpAndSettle();
      expect(find.byType(ProSheet), findsNothing);
      expect(c.read(sourceListProvider).length, 1);

      // Once a file is picked, the import calls this.
      final id = c.read(serverActionsProvider).useLocal();
      await t.pumpAndSettle();
      final sources = c.read(sourceListProvider);
      expect(sources.map((s) => s.type), [SourceType.custom, SourceType.local]);
      // A fresh id, and it becomes the active source.
      expect(sources.last.id, allOf(id, isNot('loc')));
      expect(c.read(activeSourceProvider).id, id);
      // One local source only: a second call reuses it.
      expect(c.read(serverActionsProvider).useLocal(), id);
      expect(c.read(sourceListProvider).length, 2);
      // Import stays offered; a second server is still Pro.
      expect(add, findsOneWidget);
      await t.tap(find.text('Add server'));
      await t.pumpAndSettle();
      expect(find.byType(ProSheet), findsOneWidget);
    });

    testWidgets('not offered on Android', (t) async {
      isAndroid = true;
      addTearDown(() => isAndroid = false);
      await _pump(t, [_one]);
      expect(add, findsNothing);
    });

    testWidgets('its row has no Edit, and Remove says what is deleted',
        (t) async {
      for (final id in ['c1', 'c2']) {
        File(p.join(docs.path, 'downloads', 'loc', id, 'metadata.json'))
          ..createSync(recursive: true)
          ..writeAsStringSync('{}');
        Directory(p.join(docs.path, 'downloads', 'loc', id, 'pages')).createSync();
      }
      final manager = DownloadManager(baseDir: docs.path);
      addTearDown(manager.dispose);
      await t.runAsync(manager.init);
      SharedPreferences.setMockInitialValues({
        'server_sources': jsonEncode([_one.toJson(), local.toJson()]),
        'active_source_id': 'loc',
      });
      FlutterSecureStorage.setMockInitialValues({});
      final c = ProviderContainer(overrides: [
        sharedPrefsProvider.overrideWithValue(await SharedPreferences.getInstance()),
        proStoreProvider.overrideWithValue(FakeProStore()),
        docsDirProvider.overrideWith((_) async => docs.path),
        connectivityProvider.overrideWith(() => _Connectivity(true)),
        downloadManagerProvider.overrideWithValue(manager),
      ]);
      addTearDown(c.dispose);
      await t.pumpWidget(UncontrolledProviderScope(
          container: c, child: const MaterialApp(home: ServersScreen())));
      await t.pump();

      expect(find.textContaining('On this i'), findsOneWidget);
      expect(find.text('2 comics'), findsOneWidget);
      await t.tap(find.byTooltip('On this device options'));
      await t.pumpAndSettle();
      expect(find.text('Edit'), findsNothing);
      await t.tap(find.text('Remove'));
      await t.pumpAndSettle();
      expect(find.textContaining('This deletes 2 comics from this i'),
          findsOneWidget);

      await t.tap(find.widgetWithText(TextButton, 'Delete'));
      await _settle(t);
      expect(c.read(sourceListProvider).map((s) => s.id), ['one']);
      expect(c.read(activeSourceProvider).id, 'one');
      expect(Directory(p.join(docs.path, 'downloads', 'loc')).existsSync(), false);
    });
  });
}
