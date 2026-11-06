import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:comic_reader_app/services/app_logger.dart';
import 'package:comic_reader_app/services/komga_client.dart';
import 'package:comic_reader_app/services/local_session_store.dart';

Map<String, dynamic> book(String id,
        {double sort = 1, int pages = 20, Map<String, dynamic>? progress, bool deleted = false}) =>
    {
      'id': id,
      'seriesId': 's1',
      'seriesTitle': 'Saga',
      'name': 'Saga $id',
      'deleted': deleted,
      'media': {'pagesCount': pages, 'status': 'READY'},
      'metadata': {
        'title': 'Chapter $id',
        'number': '$sort',
        'numberSort': sort,
        'summary': 'sum',
        'releaseDate': '2012-03-14',
        'authors': [
          {'name': 'Brian K. Vaughan', 'role': 'writer'},
          {'name': 'Fiona Staples', 'role': 'penciller'},
        ],
      },
      'readProgress': progress,
    };

final series = {
  'id': 's1',
  'name': 'Saga',
  'created': '2024-01-01T00:00:00Z',
  'lastModified': '2024-02-01T00:00:00Z',
  'booksCount': 3,
  'metadata': {'title': 'Saga', 'publisher': 'Image', 'genres': ['Sci-Fi'], 'summary': 'Space opera'},
  'booksMetadata': {
    'releaseDate': '2012-03-14',
    'authors': [
      {'name': 'Brian K. Vaughan', 'role': 'writer'},
    ],
  },
};

void main() {
  late List<http.Request> requests;

  setUp(() => AppLogger.init(logDirFactory: () async => null));
  tearDown(AppLogger.resetForTest);

  KomgaClient client(Map<String, Object> routes) {
    requests = [];
    return KomgaClient(
      baseUrl: 'http://k',
      deviceId: 'd',
      authHeaders: const {'X-API-Key': 'key'},
      httpClient: MockClient((req) async {
        requests.add(req);
        final body = routes['${req.method} ${req.url.path}'];
        if (body == null) return http.Response('', 404);
        if (body is int) return http.Response('', body);
        return http.Response(jsonEncode(body), 200);
      }),
    );
  }

  test('fetchSync maps series, issues and progress', () async {
    final c = client({
      'POST /api/v1/series/list': {'content': [series]},
      'POST /api/v1/books/list': {
        'content': [
          book('b2', sort: 2, progress: {'page': 5, 'completed': false, 'lastModified': '2024-03-01T00:00:00Z'}),
          book('b1', sort: 1, progress: {'page': 3, 'completed': true, 'lastModified': '2024-03-02T00:00:00Z'}),
          book('b3', sort: 3, deleted: true),
        ],
      },
    });
    final r = await c.fetchSync(since: 0);
    expect(r.seriesIds, ['s1']);
    expect(r.serverHasQueues, isFalse);
    final s = r.series.single;
    expect(s['name'], 'Saga');
    expect(s['cover_url'], '/api/v1/series/s1/thumbnail');
    expect(s['publisher'], 'Image');
    expect(s['writer'], 'Brian K. Vaughan');
    expect(s['year'], 2012);
    final issues = (s['issues'] as List).cast<Map<String, dynamic>>();
    expect(issues.map((i) => i['id']), ['b1', 'b2']);
    expect(issues.first['cover_url'], '/api/v1/books/b1/thumbnail');
    expect(issues.first['penciller'], 'Fiona Staples');
    final progress = {for (final p in r.progress) p['comic_id']: p};
    expect(progress['b1']!['current_page'], 20, reason: 'completed reads as finished');
    expect(progress['b2']!['current_page'], 4, reason: 'Komga page 5 is app page 4');
    expect(progress['b2']!['total_pages'], 20);
    expect(r.progressIds.toSet(), {'b1', 'b2'});
    expect(requests.first.headers['X-API-Key'], 'key');
    expect(requests.first.url.queryParameters['unpaged'], 'true');
  });

  test('updateProgress sends completed or 1-based page', () async {
    final c = client({'PATCH /api/v1/books/b1/read-progress': 204});
    await c.updateProgress(comicId: 'b1', currentPage: 4, totalPages: 20);
    await c.updateProgress(comicId: 'b1', currentPage: 20, totalPages: 20);
    expect(jsonDecode(requests[0].body), {'page': 5});
    expect(jsonDecode(requests[1].body), {'completed': true});
  });

  test('batchDeleteProgress deletes each book', () async {
    final c = client({'DELETE /api/v1/books/b1/read-progress': 204, 'DELETE /api/v1/books/b2/read-progress': 204});
    await c.batchDeleteProgress(['b1', 'b2']);
    expect(requests.map((r) => r.url.path), [
      '/api/v1/books/b1/read-progress',
      '/api/v1/books/b2/read-progress',
    ]);
  });

  test('pageUrl is 1-based', () {
    expect(client({}).pageUrl('b1', 0), 'http://k/api/v1/books/b1/pages/1');
  });

  test('getComicInfo reads media.pagesCount', () async {
    final info = await client({'GET /api/v1/books/b1': book('b1', pages: 24)}).getComicInfo('b1');
    expect(info.pageCount, 24);
    expect(info.series, 'Saga');
  });

  test('fetchSeriesDetail carries issue progress', () async {
    final d = await client({
      'GET /api/v1/series/s1': series,
      'POST /api/v1/books/list': {
        'content': [book('b1', progress: {'page': 3, 'completed': false, 'lastModified': 'x'})],
      },
    }).fetchSeriesDetail('s1');
    expect(d.issues.single.status, 'in_progress');
    expect(d.issues.single.currentPage, 2);
    expect(jsonDecode(requests.last.body)['condition']['seriesId']['value'], 's1');
  });

  test('checkConnection is false on 401', () async {
    expect(await client({'GET /api/v2/users/me': 401}).checkConnection(), isFalse);
    expect(await client({'GET /api/v2/users/me': {'id': 'u'}}).checkConnection(), isTrue);
  });

  test('settings, sessions and queues stay local', () async {
    final dir = await Directory.systemTemp.createTemp('komga_sessions_');
    addTearDown(() => dir.delete(recursive: true));
    final store = LocalSessionStore('${dir.path}/sessions.json');
    requests = [];
    final c = KomgaClient(
        baseUrl: 'http://k', deviceId: 'd', sessions: store,
        httpClient: MockClient((req) async {
          requests.add(req);
          return http.Response('', 404);
        }));
    expect(c.getSettings(), throwsUnsupportedError);
    await c.postReadingSession(
        comicId: 'b1', seriesId: 's1', startedAt: DateTime(2024), pagesRead: 3, durationS: 60);
    expect(requests, isEmpty);
    expect((await store.all()).single.pagesRead, 3);
    expect((await c.fetchStatsSummary()).allTime.pagesRead, 3);
    expect((await c.fetchStatsHistory()).total, 1);
  });

  test('books that are not READY and deleted series are left out', () async {
    final broken = book('b9', sort: 9)..['media'] = {'pagesCount': 12, 'status': 'ERROR'};
    final r = await client({
      'POST /api/v1/series/list': {
        'content': [series, {...series, 'id': 's2', 'deleted': true}],
      },
      'POST /api/v1/books/list': {'content': [book('b1'), broken]},
    }).fetchSync(since: 0);
    expect(r.seriesIds, ['s1']);
    expect((r.series.single['issues'] as List).map((i) => i['id']), ['b1']);
  });
}
