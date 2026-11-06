import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:comic_reader_app/services/app_logger.dart';
import 'package:comic_reader_app/services/kavita_client.dart';

// Shapes as Kavita 0.9.1 returns them (checked against a live server).
Map<String, dynamic> chapter(int id,
        {String number = '1',
        double sort = 1,
        int pages = 20,
        int read = 0,
        bool special = false,
        String titleName = ''}) =>
    {
      'id': id,
      'range': number,
      'number': number,
      'minNumber': sort,
      'sortOrder': sort,
      'pages': pages,
      'pagesRead': read,
      'isSpecial': special,
      'title': special ? 'Annual' : number,
      'titleName': titleName,
      'summary': 'sum $id',
      'releaseDate': '2012-03-14T00:00:00',
      'lastReadingProgressUtc':
          read > 0 ? '2024-03-01T10:00:00.1234567' : '0001-01-01T00:00:00',
      'files': [
        {'filePath': '/comics/Saga/Saga #$number.cbz'},
      ],
      'writers': [
        {'name': 'Brian K. Vaughan'},
      ],
      'pencillers': [
        {'name': 'Fiona Staples'},
      ],
      'coverArtists': [
        {'name': 'Fiona Staples'},
      ],
      'publishers': [
        {'name': 'Image'},
      ],
      'genres': [
        {'id': 1, 'title': 'Sci-Fi'},
      ],
    };

Map<String, dynamic> volume(int id, int number, List<Map<String, dynamic>> chapters,
        {String? name}) =>
    {
      'id': id,
      'number': number,
      'minNumber': number,
      'name': name ?? '$number',
      'chapters': chapters,
    };

final series = {
  'id': 7,
  'name': 'Saga',
  'libraryId': 3,
  'created': '2024-01-01T00:00:00',
  'lastChapterAddedUtc': '2024-02-01T00:00:00.5',
};

void main() {

  test('a changed chapter gives new cover URLs and a newer series updated_at', () {
    Map<String, dynamic> stamped(String at) => {...chapter(1), 'lastModifiedUtc': at};
    final before = kavitaSeriesToSync(series, [volume(10, 1, [stamped('2024-03-01T00:00:00')])]);
    final after = kavitaSeriesToSync(series, [volume(10, 1, [stamped('2024-05-01T00:00:00')])]);
    expect(after['updated_at'], '2024-05-01T00:00:00Z');
    expect(after['cover_url'], isNot(before['cover_url']));
    String issueCover(Map<String, dynamic> s) => (s['issues'] as List).first['cover_url'] as String;
    expect(issueCover(after), isNot(issueCover(before)));
    expect(kavitaSeriesToSync(series, [volume(10, 1, [stamped('2024-03-01T00:00:00')])])['cover_url'],
        before['cover_url']);
  });
  late List<http.Request> requests;

  setUp(() => AppLogger.init(logDirFactory: () async => null));
  tearDown(AppLogger.resetForTest);

  KavitaClient client(Map<String, Object> routes) {
    requests = [];
    return KavitaClient(
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

  // Loose issues sit in Kavita's -100000 volume; a volume file is a chapter
  // numbered -100000 in a real volume; specials sit in the 100000 volume.
  final volumes = [
    volume(30, 100000, [chapter(5, number: '-100000', special: true, sort: 0)]),
    volume(20, -100000, [
      chapter(2, number: '2', sort: 2, read: 4),
      chapter(1, number: '1', sort: 1, read: 20),
      chapter(9, number: '9', sort: 9, pages: 0),
    ]),
    volume(10, 1, [chapter(4, number: '-100000', sort: -100000)]),
  ];

  test('fetchSync maps series, chapters as issues, and progress', () async {
    final c = client({
      'POST /api/Series/all-v2': [series],
      'GET /api/Series/volumes': volumes,
    });
    final r = await c.fetchSync(since: 0);
    expect(r.seriesIds, ['7']);
    expect(r.serverHasQueues, isFalse);
    final s = r.series.single;
    expect(s['name'], 'Saga');
    expect(s['cover_url'], startsWith('/api/Image/series-cover?seriesId=7'));
    expect(s['updated_at'], '2024-02-01T00:00:00.5Z');
    expect(s['publisher'], 'Image');
    expect(s['genres'], ['Sci-Fi']);
    expect(s['writer'], 'Brian K. Vaughan');
    expect(s['year'], 2012);
    final issues = (s['issues'] as List).cast<Map<String, dynamic>>();
    expect(issues.map((i) => i['id']), ['4', '1', '2', '5'],
        reason: 'volumes, then loose chapters, then specials; empty left out');
    expect(issues.map((i) => i['number']), ['1', '1', '2', null],
        reason: 'a volume file takes its volume name');
    expect(issues.last['title'], 'Annual');
    expect(issues[1]['cover_url'], startsWith('/api/Image/chapter-cover?chapterId=1'));
    expect(issues[1]['name'], 'Saga #1.cbz');
    expect(issues[1]['cover_date'], '2012-03-14');
    expect(issues[1]['penciller'], 'Fiona Staples');
    final progress = {for (final p in r.progress) p['comic_id']: p};
    expect(progress['1']!['current_page'], 20, reason: 'finished');
    expect(progress['2']!['current_page'], 4, reason: 'pages read = 0-based page');
    expect(progress['2']!['updated_at'], '2024-03-01T10:00:00.1234567Z');
    expect(r.progressIds.toSet(), {'1', '2'});
    expect(requests.first.headers['X-API-Key'], 'key');
    expect(requests.last.url.queryParameters['seriesId'], '7');
  });

  test('fetchSync reports per-series progress', () async {
    final c = client({
      'POST /api/Series/all-v2': [series, {...series, 'id': 8}],
      'GET /api/Series/volumes': volumes,
    });
    final seen = <(int, int)>[];
    await c.fetchSync(since: 0, onSeries: (d, t) => seen.add((d, t)));
    expect(seen, [(0, 2), (1, 2), (2, 2)]);
  });

  test('updateProgress posts pageNum with the parent ids from sync', () async {
    final c = client({
      'POST /api/Series/all-v2': [series],
      'GET /api/Series/volumes': volumes,
      'POST /api/Reader/progress': 200,
    });
    await c.fetchSync(since: 0);
    await c.updateProgress(comicId: '2', currentPage: 4, totalPages: 20);
    await c.updateProgress(comicId: '2', currentPage: 25, totalPages: 20);
    final posts = requests.where((r) => r.url.path == '/api/Reader/progress');
    expect(posts.map((r) => jsonDecode(r.body)), [
      {'volumeId': 20, 'chapterId': 2, 'pageNum': 4, 'seriesId': 7, 'libraryId': 3},
      {'volumeId': 20, 'chapterId': 2, 'pageNum': 20, 'seriesId': 7, 'libraryId': 3},
    ]);
  });

  test('updateProgress asks chapter-info for unknown parents, once', () async {
    final c = client({
      'GET /api/Reader/chapter-info': {'volumeId': 20, 'seriesId': 7, 'libraryId': 3},
      'POST /api/Reader/progress': 200,
    });
    await c.updateProgress(comicId: '2', currentPage: 1, totalPages: 20);
    await c.updateProgress(comicId: '2', currentPage: 2, totalPages: 20);
    expect(requests.map((r) => r.url.path), [
      '/api/Reader/chapter-info',
      '/api/Reader/progress',
      '/api/Reader/progress',
    ]);
    expect(jsonDecode(requests[1].body)['seriesId'], 7);
  });

  test('batchDeleteProgress marks chapters unread per series', () async {
    final c = client({
      'GET /api/Series/7': series,
      'GET /api/Series/volumes': volumes,
      'POST /api/Reader/mark-multiple-unread': 200,
    });
    await c.fetchSeriesRaw('7');
    await c.batchDeleteProgress(['1', '2']);
    expect(jsonDecode(requests.last.body),
        {'seriesId': 7, 'volumeIds': [], 'chapterIds': [1, 2]});
  });

  test('pageUrl is 0-based and carries the key', () {
    expect(client({}).pageUrl('2', 0),
        'http://k/api/Reader/image?chapterId=2&page=0&apiKey=key');
  });

  test('getComicInfo reads the chapter', () async {
    final info = await client({'GET /api/Chapter': chapter(2, number: '2', pages: 24)})
        .getComicInfo('2');
    expect(info.pageCount, 24);
    expect(info.number, '2');
    expect(info.title, 'Saga #2.cbz');
  });

  test('fetchSeriesDetail carries issue progress', () async {
    final d = await client({
      'GET /api/Series/7': series,
      'GET /api/Series/volumes': volumes,
    }).fetchSeriesDetail('7');
    final byId = {for (final i in d.issues) i.id: i};
    expect(byId['2']!.status, 'in_progress');
    expect(byId['2']!.currentPage, 4);
    expect(byId['1']!.status, 'completed');
  });

  test('fetchIssueCredits joins roles per person', () async {
    final credits = await client({'GET /api/Chapter': chapter(2)}).fetchIssueCredits('2');
    expect(credits!.map((x) => (x.name, x.role)).toList(), [
      ('Brian K. Vaughan', 'writer'),
      ('Fiona Staples', 'penciller, cover'),
    ]);
  });

  test('checkConnection is false on 401', () async {
    expect(await client({'GET /api/Library/libraries': 401}).checkConnection(), isFalse);
    expect(await client({'GET /api/Library/libraries': []}).checkConnection(), isTrue);
  });

  test('login trades a username and password for the auth key', () async {
    final c = client({
      'POST /api/Account/login': {'username': 'u', 'token': 'jwt', 'apiKey': 'ak'},
    });
    expect(await c.login('u', 'pw'), 'ak');
    expect(jsonDecode(requests.single.body), {'username': 'u', 'password': 'pw'});
    expect(await client({'POST /api/Account/login': 401}).login('u', 'x'), isNull);
  });
}
