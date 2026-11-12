import 'dart:io';

import 'package:comic_reader_app/config/source_urls.dart';
import 'package:comic_reader_app/models/server_source.dart';
import 'package:comic_reader_app/services/app_logger.dart';
import 'package:comic_reader_app/services/mirror/mirror_database.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:comic_reader_app/services/opds_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// Fixtures are real feeds recorded from the Komga and Kavita demo servers
// (2026-11-11). Kavita's API key is replaced with KAVITA_API_KEY.
String fixture(String server, String path, String query) {
  final name = path.replaceAll(RegExp(r'^/+'), '').replaceAll('/', '_') +
      (query.isEmpty ? '' : '__$query');
  return File('test/fixtures/opds/$server/$name.xml').readAsStringSync();
}

const komgaBase = 'https://demo.getgutter.app';
const komgaCatalog = '/opds/v1.2/catalog';
const kavitaBase = 'https://kavita.example.com';
const kavitaCatalog = '/api/opds/KAVITA_API_KEY';

/// A client whose server answers from the recorded fixtures (404 for any
/// path without one). [requests] gets every request it is sent.
OpdsClient fixtureClient(String server, List<http.Request> requests,
    {Map<String, String> authHeaders = const {}, int maxFeeds = 2000}) {
  final komga = server == 'komga';
  return OpdsClient(
    baseUrl: komga ? komgaBase : kavitaBase,
    catalogPath: komga ? komgaCatalog : kavitaCatalog,
    deviceId: 'd',
    authHeaders: authHeaders,
    maxFeeds: maxFeeds,
    httpClient: MockClient((req) async {
      requests.add(req);
      try {
        return http.Response(fixture(server, req.url.path, req.url.query), 200,
            headers: {'content-type': 'application/atom+xml;charset=utf-8'});
      } on FileSystemException {
        return http.Response('not found', 404);
      }
    }),
  );
}

const _feedHead = '<feed xmlns="http://www.w3.org/2005/Atom" '
    'xmlns:pse="http://vaemendis.net/opds-pse/ns"><id>x</id><title>Root</title>';

String _book(String id, String streamHref, {int count = 10}) =>
    '<entry><id>$id</id><title>Book $id</title>'
    '<link rel="http://vaemendis.net/opds-pse/stream" type="image/jpeg" '
    'href="$streamHref" pse:count="$count"/></entry>';

/// A client for one hand-written feed at [path] (everything else 404).
OpdsClient feedClient(Map<String, String> feeds, List<http.Request> requests,
        {String catalogPath = '/opds'}) =>
    OpdsClient(
      baseUrl: 'https://comics.example.com',
      catalogPath: catalogPath,
      deviceId: 'd',
      authHeaders: const {'Authorization': 'Basic dTpw'},
      httpClient: MockClient((req) async {
        requests.add(req);
        final body = feeds[req.url.toString()];
        return body == null
            ? http.Response('nope', 404)
            : http.Response(body, 200);
      }),
    );

void main() {
  setUp(() => AppLogger.init(logDirFactory: () async => null));
  tearDown(AppLogger.resetForTest);

  group('parseOpdsFeed', () {
    test('Komga series feed: PSE template, count, covers, next page', () {
      final feed = parseOpdsFeed(
          fixture('komga', '/opds/v1.2/series/0S53S8N93CWXF', ''));
      expect(feed.title, 'Pepper&Carrot');
      expect(feed.next,
          'https://demo.getgutter.app/opds/v1.2/series/0S53S8N93CWXF?page=1');
      expect(feed.entries, hasLength(20));
      final first = feed.entries.first;
      expect(first.title, 'Potion of Flight');
      expect(first.stream!.href, endsWith('/pages/{pageNumber}'));
      expect(first.stream!.count, greaterThan(0));
      expect(first.thumbnail, endsWith('/thumbnail/small'));
      expect(first.image, endsWith('/thumbnail'));
      expect(first.navigation, isNull);
    });

    test('Kavita series feed: p5-prefixed count, relative hrefs, glyphs', () {
      final feed =
          parseOpdsFeed(fixture('kavita', '$kavitaCatalog/series/6', ''));
      expect(feed.image,
          '/api/image/series-cover?seriesId=6&apiKey=KAVITA_API_KEY');
      final e = feed.entries.single;
      // The read-state glyph Kavita puts before every title is dropped.
      expect(e.title, 'Crime Does Not Pay - Issue #147');
      expect(e.stream!.count, 36);
      expect(
          e.stream!.href,
          '$kavitaCatalog/image?libraryId=1&seriesId=6&volumeId=6'
          '&chapterId=57&pageNumber={pageNumber}');
    });

    test('navigation entries carry their subsection link', () {
      final feed = parseOpdsFeed(fixture('komga', komgaCatalog, ''));
      final all = feed.entries.firstWhere((e) => e.id == 'allSeries');
      expect(all.navigation, 'https://demo.getgutter.app/opds/v1.2/series');
      expect(all.stream, isNull);
    });

    test('a non-Atom body is a FormatException', () {
      expect(() => parseOpdsFeed('<html><body>Komga</body></html>'),
          throwsFormatException);
      expect(() => parseOpdsFeed('not xml at all'), throwsFormatException);
    });
  });

  group('fetchSync crawl', () {
    test('Komga demo: every series once, pages followed, views skipped',
        () async {
      final requests = <http.Request>[];
      final client = fixtureClient('komga', requests);
      final sync = await client.fetchSync(since: 0);

      final names = [for (final s in sync.series) s['name']];
      expect(names, [
        'Adventures into the Unknown (1948)',
        'Crime Does Not Pay (1942)',
        'Ghost Comics (1951)',
        'Pepper&Carrot',
        'Planet Comics (1940)',
        'Strange Worlds (1950)',
      ]);
      final pc = sync.series.firstWhere((s) => s['name'] == 'Pepper&Carrot');
      expect(pc['issues'], hasLength(40)); // 20 + 20 on the next page
      expect(pc['issue_count'], 40);
      // Komga's series entries have no image: the first book's stands in.
      expect(pc['cover_url'], startsWith('/opds/v1.2/books/'));
      expect(pc['cover_url'], endsWith('/thumbnail'));
      final issue = (pc['issues'] as List).first as Map<String, dynamic>;
      expect(issue['name'], 'Potion of Flight');
      expect(issue['cover_url'], endsWith('/thumbnail/small'));
      expect(issue['total_pages'], greaterThan(0));

      // Root views (Keep Reading, On Deck, Latest, collections…) are never
      // crawled; the library's series links are the same feeds, fetched once.
      final paths = [for (final r in requests) r.url.toString()];
      expect(paths.toSet(), hasLength(paths.length));
      expect(paths, hasLength(11));
      expect(paths.where((p) => RegExp('keep|ondeck|latest|collections|readlists|publishers').hasMatch(p)),
          isEmpty);

      expect(sync.seriesIds, [for (final s in sync.series) s['id']]);
      expect(sync.serverHasQueues, isFalse);
    });

    test('Kavita demo: library → series, names cleaned, continue-reading skipped',
        () async {
      final requests = <http.Request>[];
      final sync = await fixtureClient('kavita', requests).fetchSync(since: 0);
      final names = [for (final s in sync.series) s['name']];
      expect(names, [
        'Adventures into the Unknown',
        'Crime Does Not Pay',
        'Ghost Comics',
        'Pepper&Carrot',
        'Planet Comics',
        'Strange Worlds',
      ]);
      final pc = sync.series.firstWhere((s) => s['name'] == 'Pepper&Carrot');
      final issues = (pc['issues'] as List).cast<Map<String, dynamic>>();
      // 41 entries: the "Continue Reading from:" copy of #2 is not an issue.
      expect(issues, hasLength(40));
      expect(issues.first['name'], 'Pepper&Carrot - Issue #1 - Potion of Flight');
      expect(issues.first['number'], '1');
      expect(issues[1]['number'], '2');
      expect(pc['cover_url'],
          '/api/image/series-cover?seriesId=1&apiKey=KAVITA_API_KEY');
      expect(requests, hasLength(9));
    });

    test('progress stays on the device: none sent, none pruned', () async {
      final sync = await fixtureClient('komga', []).fetchSync(since: 0);
      final ids = [
        for (final s in sync.series)
          for (final i in s['issues'] as List) (i as Map)['id'] as String,
      ];
      expect(sync.progress, isEmpty);
      expect(sync.progressIds, unorderedEquals(ids));
    });

    test('Kavita stamps every entry with the request time: no updated_at',
        () async {
      final sync = await fixtureClient('kavita', []).fetchSync(since: 0);
      expect(sync.series.map((s) => s['updated_at']).toSet(), {null});
      final komga = await fixtureClient('komga', []).fetchSync(since: 0);
      expect(komga.series.first['updated_at'], isNotNull);
    });

    test('stops at maxFeeds', () async {
      final requests = <http.Request>[];
      await fixtureClient('komga', requests, maxFeeds: 3).fetchSync(since: 0);
      expect(requests, hasLength(3));
    });

    test('entries without page streaming are skipped', () async {
      final sync = await feedClient({
        'https://comics.example.com/opds': '$_feedHead'
            '<entry><id>epub</id><title>No PSE</title>'
            '<link rel="http://opds-spec.org/acquisition" href="/dl/1.cbz"/></entry>'
            '${_book('b1', '/opds/b1/{pageNumber}')}</feed>',
      }, []).fetchSync(since: 0);
      final issues = sync.series.single['issues'] as List;
      expect(issues, hasLength(1));
      expect((issues.single as Map)['name'], 'Book b1');
    });
  });

  group('same-origin only', () {
    test('links to another host are never requested or used', () async {
      final requests = <http.Request>[];
      final sync = await feedClient({
        'https://comics.example.com/opds': '$_feedHead'
            '<entry><id>n</id><title>Elsewhere</title>'
            '<link rel="subsection" href="https://evil.example/opds/feed"/></entry>'
            '${_book('far', 'https://evil.example/pages/{pageNumber}')}'
            '${_book('near', '/opds/near/{pageNumber}')}</feed>',
      }, requests).fetchSync(since: 0);
      expect(requests.map((r) => r.url.host).toSet(), {'comics.example.com'});
      final issues = sync.series.single['issues'] as List;
      expect([for (final i in issues) (i as Map)['name']], ['Book near']);
      // Credentials went only to the source's own origin.
      expect(requests.every((r) => r.headers['Authorization'] == 'Basic dTpw'),
          isTrue);
    });

    test('a same-host link with another scheme or port is rebased onto the '
        "source's origin", () async {
      final requests = <http.Request>[];
      await feedClient({
        'https://comics.example.com/opds': '$_feedHead'
            '<entry><id>n</id><title>Series</title>'
            '<link rel="subsection" href="http://comics.example.com:8080/opds/s"/></entry></feed>',
        'https://comics.example.com/opds/s': '$_feedHead'
            '${_book('b', '/opds/b/{pageNumber}')}</feed>',
      }, requests).fetchSync(since: 0);
      expect([for (final r in requests) r.url.toString()], [
        'https://comics.example.com/opds',
        'https://comics.example.com/opds/s',
      ]);
    });
  });

  group('page streaming URLs', () {
    test('Komga: 0-based page into the template', () async {
      final client = fixtureClient('komga', []);
      final sync = await client.fetchSync(since: 0);
      final issue = ((sync.series.first['issues'] as List).first as Map);
      final id = issue['id'] as String;
      expect(client.pageUrl(id, 0),
          'https://demo.getgutter.app/opds/v1.2/books/0S58B20S7CPBG/pages/0');
      expect(client.pageUrl(id, 51), endsWith('/pages/51'));
      expect((await client.getComicInfo(id)).pageCount, 52);
    });

    test("Kavita: the id is relative to the catalog, so it doesn't carry "
        'the key; the URL does', () async {
      final client = fixtureClient('kavita', []);
      final sync = await client.fetchSync(since: 0);
      final crime = sync.series.firstWhere((s) => s['name'] == 'Crime Does Not Pay');
      final id = ((crime['issues'] as List).single as Map)['id'] as String;
      expect(id, isNot(contains('KAVITA')));
      expect(
          client.pageUrl(id, 3),
          '$kavitaBase$kavitaCatalog/image?libraryId=1&seriesId=6'
          '&volumeId=6&chapterId=57&pageNumber=3');
      expect((await client.getComicInfo(id)).pageCount, 36);

      // SourceUrls (covers, downloads) builds the same page URL.
      const source = ServerSource(
          id: 's', name: 'K', type: SourceType.opds, baseUrl: kavitaBase,
          authType: AuthType.none, catalogPath: kavitaCatalog);
      expect(source.page(id, 3), client.pageUrl(id, 3));
      expect(source.comicCover(id), client.pageUrl(id, 0));
    });

    test('a {maxWidth} placeholder gets a width', () {
      final id = opdsComicId(4, '/opds/p/{pageNumber}?w={maxWidth}', '/opds');
      expect(opdsPageUrl('https://h', '/opds', id, 2), 'https://h/opds/p/2?w=2048');
    });
  });

  test('series detail re-reads that series feed', () async {
    final client = fixtureClient('komga', []);
    final sync = await client.fetchSync(since: 0);
    final pc = sync.series.firstWhere((s) => s['name'] == 'Pepper&Carrot');
    final detail = await client.fetchSeriesDetail(pc['id'] as String);
    expect(detail.issues, hasLength(40));
  });

  group('probeStatus', () {
    test('an OPDS feed is 200, anything else is not', () async {
      Future<int?> probe(int status, String body) => OpdsClient(
            baseUrl: 'https://h',
            catalogPath: '/opds',
            deviceId: 'd',
            httpClient: MockClient((_) async => http.Response(body, status)),
          ).probeStatus();
      expect(await probe(200, fixture('komga', komgaCatalog, '')), 200);
      expect(await probe(200, '<html>login page</html>'), isNull);
      expect(await probe(401, 'Unauthorized'), 401);
    });
  });

  test('the mirror keeps local progress across syncs and lists the series',
      () async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final db = MirrorDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final client = fixtureClient('kavita', []);
    await db.applySync(await client.fetchSync(since: 0));
    final first = (await db.select(db.issueRows).get()).first.id;
    await db.saveProgressLocal(comicId: first, currentPage: 3, totalPages: 52);

    await db.applySync(await client.fetchSync(since: 0));
    final progress = await db.select(db.progressRows).get();
    expect(progress.map((r) => (r.comicId, r.currentPage)), [(first, 3)]);
    expect((await db.select(db.seriesRows).get()), hasLength(6));
    expect((await db.select(db.issueRows).get()), hasLength(4 + 1 + 4 + 40 + 4 + 4));
  });

  test('progress writes stay local', () async {
    final requests = <http.Request>[];
    final client = feedClient({}, requests);
    await client.updateProgress(comicId: 'x', currentPage: 1, totalPages: 2);
    await client.batchDeleteProgress(['x']);
    expect(requests, isEmpty);
  });
}
