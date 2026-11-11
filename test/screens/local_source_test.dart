import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:comic_reader_app/config/platform.dart';
import 'package:comic_reader_app/models/series.dart';
import 'package:comic_reader_app/models/server_source.dart';
import 'package:comic_reader_app/providers/cache_providers.dart';
import 'package:comic_reader_app/providers/connectivity_provider.dart';
import 'package:comic_reader_app/providers/download_provider.dart';
import 'package:comic_reader_app/providers/local_import_provider.dart';
import 'package:comic_reader_app/providers/mirror_provider.dart';
import 'package:comic_reader_app/providers/pro_provider.dart';
import 'package:comic_reader_app/providers/providers.dart';
import 'package:comic_reader_app/screens/library_screen.dart';
import 'package:comic_reader_app/services/app_logger.dart';
import 'package:comic_reader_app/services/download_manager.dart';
import 'package:comic_reader_app/services/local_client.dart';
import 'package:comic_reader_app/services/local_import.dart';
import 'package:comic_reader_app/services/mirror/mirror_database.dart';
import 'package:comic_reader_app/widgets/download_button.dart';
import 'package:comic_reader_app/widgets/issue_list_view.dart';
import 'package:comic_reader_app/widgets/local_import_button.dart';
import 'package:comic_reader_app/widgets/pro_sheet.dart';
import 'package:comic_reader_app/widgets/series_detail_header.dart';

import '../providers/pro_provider_test.dart' show FakeProStore;
import '../services/local_import_test.dart' show writeZip;

/// A real 1×1 PNG, so cover tiles decode it.
final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');

const local = ServerSource.local(id: 'loc', isDefault: true);

class _Online extends ConnectivityNotifier {
  @override
  bool build() => true;
}

late Directory tmp;

Future<ProviderContainer> container(
    {Future<List<String>> Function()? picker,
    List<String> picked = const []}) async {
  SharedPreferences.setMockInitialValues({
    'server_sources': jsonEncode([local.toJson()]),
    'active_source_id': local.id,
  });
  FlutterSecureStorage.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final manager = DownloadManager(baseDir: tmp.path);
  final c = ProviderContainer(overrides: [
    sharedPrefsProvider.overrideWithValue(prefs),
    proStoreProvider.overrideWithValue(FakeProStore()),
    connectivityProvider.overrideWith(_Online.new),
    docsDirProvider.overrideWith((_) async => tmp.path),
    mirrorDbProvider.overrideWith((ref) {
      final db = MirrorDatabase(NativeDatabase.memory());
      ref.onDispose(db.close);
      return db;
    }),
    downloadManagerProvider.overrideWithValue(manager),
    comicFilePickerProvider.overrideWithValue(picker ?? () async => picked),
  ]);
  addTearDown(c.dispose);
  addTearDown(manager.dispose);
  return c;
}

/// Real file and isolate work only moves on the real event loop.
Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 20; i++) {
    await t.runAsync(() => Future.delayed(const Duration(milliseconds: 25)));
    await t.pump();
  }
}

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  setUp(() async {
    await AppLogger.init(logDirFactory: () async => null);
    tmp = Directory.systemTemp.createTempSync('local_source');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('the local source is always online and is not a Gutter server', () async {
    final c = await container();
    await c.read(docsDirProvider.future);
    expect(c.read(apiClientProvider), isA<LocalClient>());
    expect(c.read(isLocalSourceProvider), true);
    expect(c.read(hasMirrorProvider), true);
    expect(c.read(isCustomSourceProvider), false);
    expect(c.read(gutterFeaturesProvider), false);
  });

  test('pickAndImport: the series is in the mirror and in Downloads at once',
      () async {
    final good = writeZip(tmp, 'Saga 001.cbz', {'1.png': png, '2.png': png});
    final bad = p.join(tmp.path, 'Bad.cbz');
    File(bad).writeAsStringSync('not a zip');
    final c = await container(picked: [good, bad, good]);
    await c.read(docsDirProvider.future);
    final seen = <({int done, int total})?>[];
    c.listen(localImportProvider, (_, next) => seen.add(next));

    final outcomes = await c.read(localImportProvider.notifier).pickAndImport();

    expect(outcomes, [
      (fileName: 'Saga 001.cbz', problem: null),
      (fileName: 'Bad.cbz', problem: 'Not a CBZ file.'),
      (fileName: 'Saga 001.cbz', problem: 'Already imported.'),
    ]);
    expect(seen.first, (done: 0, total: 3));
    expect(seen.last, isNull);
    final series = await c.read(mirrorDbProvider).watchLibrary().first;
    expect(series.map((s) => s.series.name), ['Saga']);
    final done = c.read(downloadManagerProvider)!.currentState.completed;
    expect(done.map((i) => i.seriesName), ['Saga']);
    expect(done.single.sourceId, 'loc');
  });

  test('every import problem has its own message', () {
    expect({for (final e in LocalImportError.values) importProblem(e)}.length,
        LocalImportError.values.length);
  });

  group('Library', () {
    Future<ProviderContainer> pumpLibrary(WidgetTester t,
        {List<String> picked = const [], Size size = const Size(1024, 1366)}) async {
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final c = await container(picked: picked);
      // The launch sync, so the library is "empty", not "loading".
      await t.runAsync(() async {
        await c.read(docsDirProvider.future);
        await c.read(syncEngineProvider)!.sync(force: true);
      });
      await t.pumpWidget(UncontrolledProviderScope(
          container: c, child: const MaterialApp(home: LibraryScreen())));
      await settle(t);
      return c;
    }

    for (final size in const [Size(1024, 1366), Size(600, 900)]) {
      testWidgets('empty local library offers Import comics at $size', (t) async {
        await pumpLibrary(t, size: size);
        expect(t.takeException(), isNull);
        expect(find.textContaining('Import CBZ files'), findsOneWidget);
        expect(find.widgetWithText(FilledButton, 'Import comics'), findsOneWidget);
        // And the header button.
        expect(find.byTooltip('Import comics'), findsOneWidget);
        expect(find.textContaining('Offline'), findsNothing);
      });
    }

    testWidgets('no import controls on Android', (t) async {
      isAndroid = true;
      addTearDown(() => isAndroid = false);
      await pumpLibrary(t);
      expect(find.byType(LocalImportButton), findsNothing);
      expect(find.textContaining('Import CBZ files'), findsOneWidget);
    });

    testWidgets('import: the series appears, and each bad file is named',
        (t) async {
      final good = writeZip(tmp, 'Saga 001.cbz', {'1.png': png});
      final empty = writeZip(tmp, 'Notes.cbz', {'readme.txt': [1]});
      final c = await pumpLibrary(t, picked: [good, empty]);

      await t.tap(find.widgetWithText(FilledButton, 'Import comics'));
      await settle(t);

      expect(find.text('Imported 1 of 2'), findsOneWidget);
      expect(find.text('Notes.cbz: No pages found in it.'), findsOneWidget);
      await t.tap(find.text('OK'));
      await settle(t);
      expect(find.text('Saga'), findsOneWidget);
      expect(find.textContaining('Import CBZ files'), findsNothing);
      // Free: the Pro sheet never opened.
      expect(find.byType(ProSheet), findsNothing);
      expect(c.read(downloadManagerProvider)!.currentState.completed.length, 1);
    });

    testWidgets('a clean import says so in a snackbar', (t) async {
      final good = writeZip(tmp, 'Saga 001.cbz', {'1.png': png});
      await pumpLibrary(t, picked: [good]);
      await t.tap(find.byTooltip('Import comics'));
      await settle(t);
      expect(find.text('Imported 1 comic'), findsOneWidget);
    });

  });

  testWidgets('the unbuilt picker shows a message, not a crash', (t) async {
    // The real seam throws until stage 3.
    final bare = ProviderContainer();
    addTearDown(bare.dispose);
    expect(() => bare.read(comicFilePickerProvider)(), throwsUnimplementedError);

    final c = await container(picker: () => throw UnimplementedError());
    await t.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(home: Scaffold(body: LocalImportButton()))));
    await t.tap(find.text('Import comics'));
    await t.pump();
    expect(find.text('Could not open the file picker.'), findsOneWidget);
  });

  group('download controls', () {
    const issue = SeriesIssue(
        id: 'c1', name: 'Saga 001.cbz', number: '1', coverUrl: '', status: 'unread');

    Future<ProviderContainer> pumpRow(WidgetTester t, {required bool isLocal}) async {
      final c = await container();
      await t.pumpWidget(UncontrolledProviderScope(
          container: c,
          child: ProviderScope(
            overrides: [
              isLocalSourceProvider.overrideWithValue(isLocal),
              issueCoverPathsProvider.overrideWith((_) => Stream.value(const {})),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: IssueListRow(
                  issue: issue,
                  serverUrl: '',
                  seriesId: 's1',
                  seriesName: 'Saga',
                  accent: Colors.blue,
                  onTap: () {},
                  onLongPress: () {},
                ),
              ),
            ),
          )));
      await t.pump();
      return c;
    }

    testWidgets('a server issue keeps its download button', (t) async {
      await pumpRow(t, isLocal: false);
      expect(find.byType(DownloadButton), findsOneWidget);
      expect(find.byTooltip('Delete'), findsNothing);
    });

    testWidgets('an imported issue has Delete instead, and it deletes the files',
        (t) async {
      final dir = Directory(p.join(tmp.path, 'downloads', 'loc', 'c1', 'pages'))
        ..createSync(recursive: true);
      File(p.join(dir.parent.path, 'metadata.json')).writeAsStringSync('{}');
      final c = await pumpRow(t, isLocal: true);
      await t.runAsync(() => c.read(downloadManagerProvider)!.adopt('c1', 'loc'));
      expect(find.byType(DownloadButton), findsNothing);

      await t.tap(find.byTooltip('Delete'));
      await t.pump();
      expect(find.text('Delete Saga 001?'), findsOneWidget);
      await t.tap(find.widgetWithText(TextButton, 'Delete'));
      await settle(t);
      expect(dir.parent.existsSync(), false);
      expect(c.read(downloadManagerProvider)!.currentState.completed, isEmpty);
    });

    testWidgets('the series header can leave out the Download action',
        (t) async {
      final c = await container();
      Widget header(bool showDownload) => UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: SeriesDetailHeader(
                  detail: const SeriesDetail(
                      id: 's1',
                      name: 'Saga',
                      folderPath: '',
                      issueCount: 1,
                      readCount: 0,
                      coverUrl: '',
                      issues: []),
                  coverImageUrl: null,
                  isPanel: true,
                  accent: Colors.blue,
                  seriesId: 's1',
                  resumeButtonContent: const Text('Read'),
                  progress: 0,
                  showDownload: showDownload,
                ),
              ),
            ),
          ));
      await t.pumpWidget(header(false));
      await t.pump();
      expect(find.text('Download'), findsNothing);
      expect(find.text('Mark Read'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(header(true));
      await t.pump();
      expect(find.text('Download'), findsOneWidget);
    });
  });
}
