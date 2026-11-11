import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:comic_reader_app/config/source_urls.dart';
import 'package:comic_reader_app/models/server_source.dart';
import 'package:comic_reader_app/providers/providers.dart';
import 'package:comic_reader_app/services/api_client.dart';
import 'package:comic_reader_app/services/app_logger.dart';
import 'package:comic_reader_app/services/kavita_client.dart';
import 'package:comic_reader_app/services/komga_client.dart';
import 'package:comic_reader_app/services/local_client.dart';
import 'package:comic_reader_app/services/local_import.dart';
import 'package:comic_reader_app/services/mirror/mirror_database.dart';

import 'local_import_test.dart' show writeZip;

void main() {
  late Directory tmp;
  late String docs;
  late LocalClient client;
  final outcomes = <bool>[];

  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  setUp(() async {
    await AppLogger.init(logDirFactory: () async => null);
    tmp = Directory.systemTemp.createTempSync('local_client');
    docs = p.join(tmp.path, 'docs');
    outcomes.clear();
    client = LocalClient(
        libraryDir: p.join(docs, 'downloads', 'local'),
        deviceId: 'd',
        onRequestOutcome: outcomes.add);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<ImportedComic> add(String name, {int pages = 1}) => importCbz(
      cbzPath: writeZip(tmp, name, {for (var i = 1; i <= pages; i++) '$i.jpg': [i]}),
      docsDir: docs,
      sourceId: 'local');

  test('the local source counts as set up and maps to LocalClient', () {
    const s = ServerSource.local();
    expect(s.baseUrl, isNotEmpty);
    expect(s.authHeaders, isEmpty);
    expect(ServerSource.fromJson(s.toJson()).type, SourceType.local);
    final c = clientFor(s, deviceId: 'd', docsDir: '/docs');
    expect(c, isA<LocalClient>());
    expect((c as LocalClient).libraryDir, '/docs/downloads/local');
    expect(s.comicCover('c1'), startsWith(localBaseUrl));
  });

  test('clientFor is unchanged for server sources', () {
    ServerSource src(SourceType t) => ServerSource(
        id: 'x', name: 'x', type: t, baseUrl: 'http://h', authType: AuthType.none);
    expect(clientFor(src(SourceType.komga), deviceId: 'd'), isA<KomgaClient>());
    expect(clientFor(src(SourceType.kavita), deviceId: 'd'), isA<KavitaClient>());
    for (final t in [SourceType.custom, SourceType.opds]) {
      final c = clientFor(src(t), deviceId: 'd', docsDir: '/docs');
      expect(c.runtimeType, ApiClient);
      expect(c.baseUrl, 'http://h');
    }
  });

  test('an empty library syncs as empty', () async {
    final r = await client.fetchSync(since: 0);
    expect(r.series, isEmpty);
    expect(r.seriesIds, isEmpty);
    expect(r.serverHasQueues, false);
  });

  test('fetchSync groups imports by series, issues in number order', () async {
    final s10 = await add('Saga 010.cbz');
    final s2 = await add('Saga 002.cbz', pages: 3);
    final w = await add('Watchmen.cbz');
    final r = await client.fetchSync(since: 0);

    expect(r.seriesIds.toSet(), {s2.seriesId, w.seriesId});
    expect(r.progress, isEmpty);
    expect(r.progressIds.toSet(), {s10.comicId, s2.comicId, w.comicId});
    final saga = r.series.firstWhere((s) => s['id'] == s2.seriesId);
    expect(saga['name'], 'Saga');
    expect(saga['issue_count'], 2);
    expect(saga['cover_url'], '');
    expect([for (final i in saga['issues'] as List) i['id']], [s2.comicId, s10.comicId]);
    expect((saga['issues'] as List).first['number'], '2');
    expect((saga['issues'] as List).first['total_pages'], 3);

    final detail = await client.fetchSeriesDetail(s2.seriesId);
    expect(detail.issues.map((i) => i.id), [s2.comicId, s10.comicId]);
    final info = await client.getComicInfo(s2.comicId);
    expect((info.title, info.series, info.number, info.pageCount), ('Saga 002', 'Saga', '2', 3));
    expect(() => client.getComicInfo('nope'), throwsA(isA<ApiException>()));
  });

  test('the mirror keeps local progress and prunes deleted comics', () async {
    final db = MirrorDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final a = await add('Saga 001.cbz', pages: 4);
    final b = await add('Saga 002.cbz', pages: 4);
    final w = await add('Watchmen.cbz');
    await db.applySync(await client.fetchSync(since: 0));
    await db.saveProgressLocal(comicId: a.comicId, currentPage: 2, totalPages: 4);
    await db.saveProgressLocal(comicId: w.comicId, currentPage: 0, totalPages: 1);

    // A later sync must not wipe progress the server never had.
    await db.applySync(await client.fetchSync(since: 0));
    expect((await db.select(db.progressRows).get()).map((r) => r.comicId).toSet(),
        {a.comicId, w.comicId});
    expect((await db.select(db.issueRows).get()).length, 3);

    // Delete Watchmen (its only issue) and Saga 002 from disk.
    for (final id in [w.comicId, b.comicId]) {
      Directory(p.join(docs, 'downloads', 'local', id)).deleteSync(recursive: true);
    }
    await db.applySync(await client.fetchSync(since: 0));
    expect((await db.select(db.seriesRows).get()).map((r) => r.id), [a.seriesId]);
    expect((await db.select(db.issueRows).get()).map((r) => r.id), [a.comicId]);
    final progress = await db.select(db.progressRows).get();
    expect(progress.map((r) => (r.comicId, r.currentPage)), [(a.comicId, 2)]);
  });

  test('is always reachable and never touches the network', () async {
    expect(await client.probeStatus(), 200);
    expect(await client.checkConnection(), true);
    expect(outcomes, [true, true]);
    // Writes are no-ops; the mirror already has them.
    await client.updateProgress(comicId: 'c', currentPage: 1, totalPages: 2);
    await client.batchUpdateProgress([{'comic_id': 'c'}]);
    await client.batchDeleteProgress(['c']);
    expect(await client.fetchIssueCredits('c'), isNull);
    // A call with no local answer is "not found", not "offline".
    await expectLater(client.fetchCreators(), throwsA(isA<ApiException>()));
    expect(outcomes, isNot(contains(false)));
  });

  test('fetchSync fails until the documents directory is known', () {
    final c = LocalClient(libraryDir: null, deviceId: 'd');
    expect(() => c.fetchSync(since: 0), throwsStateError);
  });
}
