import '../models/bookmark.dart';
import '../models/chapter.dart';
import '../models/comic_info.dart';
import '../models/creator.dart';
import '../models/series.dart';
import '../models/sync_response.dart';
import 'api_client.dart';
import 'komga_client.dart' show LocalReaderData, withIssueStatuses;
import 'local_session_store.dart';

/// A Kavita server (0.9+) behind the [ApiClient] surface the mirror, reader
/// and progress sync use, like [KomgaClient]. A Kavita chapter is the app's
/// issue (volumes only order them); ids are Kavita's ints as strings. Auth is
/// the account's auth key in `X-API-Key` (`ServerSource.authHeaders`); page
/// images also need it as the `apiKey` query parameter.
class KavitaClient extends ApiClient with LocalReaderData {
  KavitaClient({
    required super.baseUrl,
    required super.deviceId,
    super.httpClient,
    super.onRequestOutcome,
    super.authHeaders,
    this.sessions,
  });

  @override
  final LocalSessionStore? sessions;

  String get _key => authHeaders['X-API-Key'] ?? '';

  /// chapterId → the volume, series and library ids every progress write
  /// needs, learned from the last sync or series fetch.
  final _parents = <String, ({int volumeId, int seriesId, int libraryId})>{};

  /// The account's auth key for a username and password (Kavita has no
  /// basic auth), or null when the login is refused.
  Future<String?> login(String username, String password) async {
    try {
      final u = await requestJson('POST', '/api/Account/login',
          body: {'username': username, 'password': password},
          timeout: const Duration(seconds: 10)) as Map<String, dynamic>;
      return u['apiKey'] as String?;
    } on ApiException {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> _volumes(Map<String, dynamic> series) async {
    final vols = ((await requestJson(
                'GET', '/api/Series/volumes?seriesId=${series['id']}'))
            as List<dynamic>)
        .cast<Map<String, dynamic>>();
    for (final v in vols) {
      for (final c in (v['chapters'] as List? ?? const []).cast<Map>()) {
        _parents['${c['id']}'] = (
          volumeId: v['id'] as int,
          seriesId: series['id'] as int,
          libraryId: series['libraryId'] as int,
        );
      }
    }
    return vols;
  }

  // ponytail: full pull every sync, one volumes call per series (6 at a
  // time); skip series whose lastChapterAddedUtc/latestReadDate predate
  // `since` if big libraries get slow.
  @override
  Future<SyncResponse> fetchSync({required int since}) async {
    final series = ((await requestJson('POST', '/api/Series/all-v2',
            body: {}, timeout: const Duration(minutes: 4))) as List<dynamic>)
        .cast<Map<String, dynamic>>();
    final volumes = <Object?, List<Map<String, dynamic>>>{};
    for (var i = 0; i < series.length; i += 6) {
      await Future.wait(series.skip(i).take(6).map((s) async {
        volumes[s['id']] = await _volumes(s);
      }));
    }
    final progress = [
      for (final s in series)
        for (final c in kavitaChapters(volumes[s['id']]!)) ?kavitaProgress(c),
    ];
    return SyncResponse(
      serverTime: DateTime.now().millisecondsSinceEpoch,
      series: [
        for (final s in series) kavitaSeriesToSync(s, volumes[s['id']]!),
      ],
      progress: progress,
      seriesIds: [for (final s in series) '${s['id']}'],
      progressIds: [for (final p in progress) p['comic_id'] as String],
      serverHasQueues: false,
    );
  }

  @override
  Future<Map<String, dynamic>> fetchSeriesRaw(String seriesId) async {
    final s = await requestJson('GET', '/api/Series/${Uri.encodeComponent(seriesId)}')
        as Map<String, dynamic>;
    final vols = await _volumes(s);
    return withIssueStatuses(kavitaSeriesToSync(s, vols), [
      for (final c in kavitaChapters(vols)) ?kavitaProgress(c),
    ]);
  }

  @override
  Future<SeriesDetail> fetchSeriesDetail(String seriesId) async =>
      SeriesDetail.fromJson(await fetchSeriesRaw(seriesId));

  Future<Map<String, dynamic>> _chapter(String id) async =>
      await requestJson('GET', '/api/Chapter?chapterId=${Uri.encodeQueryComponent(id)}')
          as Map<String, dynamic>;

  @override
  Future<ComicInfo> getComicInfo(String comicId) async {
    final c = await _chapter(comicId);
    final title = c['titleName'] as String? ?? '';
    return ComicInfo(
      title: title.isNotEmpty ? title : _fileName(c),
      number: _isSentinel(c['number']) ? null : c['number'] as String?,
      summary: c['summary'] as String?,
      pageCount: c['pages'] as int? ?? 0,
    );
  }

  @override
  String pageUrl(String comicId, int pageNum) =>
      kavitaPageUrl(baseUrl, comicId, pageNum, _key);

  /// [comicId]'s parent ids: from the last sync, else from the server
  /// (chapter-info also warms Kavita's page cache, which the reader wants).
  Future<({int volumeId, int seriesId, int libraryId})> _parentsOf(
      String comicId) async {
    final known = _parents[comicId];
    if (known != null) return known;
    final i = await requestJson('GET',
        '/api/Reader/chapter-info?chapterId=${Uri.encodeQueryComponent(comicId)}') as Map;
    return _parents[comicId] = (
      volumeId: i['volumeId'] as int,
      seriesId: i['seriesId'] as int,
      libraryId: i['libraryId'] as int,
    );
  }

  /// Kavita's pageNum is pages read: the app's 0-based page, and
  /// `totalPages` once finished.
  @override
  Future<void> updateProgress({
    required String comicId,
    required int currentPage,
    required int totalPages,
    List<Bookmark>? bookmarks,
    List<Chapter>? chapters,
    int? readAtMs,
  }) async {
    final p = await _parentsOf(comicId);
    await requestJson('POST', '/api/Reader/progress', body: {
      'volumeId': p.volumeId,
      'chapterId': int.parse(comicId),
      'pageNum': currentPage.clamp(0, totalPages),
      'seriesId': p.seriesId,
      'libraryId': p.libraryId,
    });
  }

  @override
  Future<void> batchUpdateProgress(List<Map<String, dynamic>> items) async {
    for (final i in items) {
      await updateProgress(
        comicId: i['comic_id'] as String,
        currentPage: i['current_page'] as int,
        totalPages: i['total_pages'] as int,
      );
    }
  }

  /// One mark-multiple-unread per series.
  @override
  Future<void> batchDeleteProgress(List<String> comicIds) async {
    final bySeries = <int, List<int>>{};
    for (final id in comicIds) {
      final p = await _parentsOf(id);
      bySeries.putIfAbsent(p.seriesId, () => []).add(int.parse(id));
    }
    for (final e in bySeries.entries) {
      await requestJson('POST', '/api/Reader/mark-multiple-unread', body: {
        'seriesId': e.key,
        'volumeIds': const [],
        'chapterIds': e.value,
      });
    }
  }

  /// The chapter's own people: one row per person, roles joined the way the
  /// credits sheet splits them.
  @override
  Future<List<Creator>?> fetchIssueCredits(String comicId) async {
    final c = await _chapter(comicId);
    final roles = <String, List<String>>{};
    for (final MapEntry(key: field, value: role) in _roles.entries) {
      for (final p in (c[field] as List? ?? const []).cast<Map>()) {
        final name = (p['name'] as String? ?? '').trim();
        if (name.isNotEmpty) roles.putIfAbsent(name, () => []).add(role);
      }
    }
    return [
      for (final e in roles.entries) Creator(name: e.key, role: e.value.join(', ')),
    ];
  }

  @override
  Future<int?> probeStatus() async {
    try {
      await requestJson('GET', '/api/Library/libraries',
          timeout: const Duration(seconds: 5));
      return 200;
    } on ApiException catch (e) {
      return e.statusCode;
    } catch (_) {
      return null;
    }
  }
}

const _roles = {
  'writers': 'writer',
  'pencillers': 'penciller',
  'inkers': 'inker',
  'colorists': 'colorist',
  'letterers': 'letterer',
  'coverArtists': 'cover',
  'editors': 'editor',
  'translators': 'translator',
};

/// A Kavita page image. Pages are 0-based, like the app's; the image
/// endpoint takes the key only as a query parameter.
String kavitaPageUrl(String baseUrl, String chapterId, int zeroBasedPage, String apiKey) =>
    '$baseUrl/api/Reader/image?chapterId=${Uri.encodeQueryComponent(chapterId)}'
    '&page=$zeroBasedPage&apiKey=${Uri.encodeQueryComponent(apiKey)}';

/// Kavita's "no number" marker: -100000 for a loose chapter's volume or a
/// volume file's chapter; 100000 for the specials volume.
bool _isSentinel(Object? n) {
  final v = n is num ? n : num.tryParse('$n');
  return v != null && v.abs() == 100000;
}

/// Kavita's UTC times come without a zone; its "never" is year 1.
String? _utc(Object? t) {
  if (t is! String || t.isEmpty || t.startsWith('0001')) return null;
  return t.endsWith('Z') || t.contains('+') ? t : '${t}Z';
}

String _fileName(Map c) {
  final files = c['files'] as List? ?? const [];
  final path = files.isEmpty ? '' : (files.first as Map)['filePath'] as String? ?? '';
  return path.split('/').last;
}

String? _first(Map c, String field) {
  final people = c[field] as List? ?? const [];
  return people.isEmpty ? null : (people.first as Map)['name'] as String?;
}

/// [volumes]' readable chapters in reading order: numbered volumes, then
/// loose chapters, then specials, each by Kavita's sort order.
List<Map<String, dynamic>> kavitaChapters(List<Map<String, dynamic>> volumes) {
  int bucket(Map v) => switch (v['number'] as int? ?? 0) {
        -100000 => 1,
        100000 => 2,
        _ => 0,
      };
  final vols = [...volumes]..sort((a, b) {
      final c = bucket(a).compareTo(bucket(b));
      return c != 0 ? c : (a['minNumber'] as num? ?? 0).compareTo(b['minNumber'] as num? ?? 0);
    });
  return [
    for (final v in vols)
      ...((v['chapters'] as List? ?? const [])
              .cast<Map<String, dynamic>>()
              .where((c) => (c['pages'] as int? ?? 0) > 0)
              .toList()
            ..sort((a, b) =>
                (a['sortOrder'] as num? ?? 0).compareTo(b['sortOrder'] as num? ?? 0)))
          .map((c) => {...c, '_volume': v}),
  ];
}

/// A Kavita series and its volumes in the Gutter `/sync` series shape, with
/// readable chapters inline as issues. Series metadata (publisher, genres,
/// summary, creators) comes from the first chapter, which saves a metadata
/// call per series.
Map<String, dynamic> kavitaSeriesToSync(
    Map<String, dynamic> series, List<Map<String, dynamic>> volumes) {
  final id = '${series['id']}';
  final chapters = kavitaChapters(volumes);
  final first = chapters.isEmpty ? const <String, dynamic>{} : chapters.first;
  final year = int.tryParse(((first['releaseDate'] as String?) ?? '').split('-').first);
  String? number(Map<String, dynamic> c) {
    if (c['isSpecial'] == true) return null;
    if (!_isSentinel(c['number'])) return c['number'] as String?;
    final v = c['_volume'] as Map;
    return _isSentinel(v['number']) ? null : v['name'] as String?;
  }

  return {
    'id': id,
    'name': series['name'] as String? ?? '',
    'updated_at': _utc(series['lastChapterAddedUtc']),
    'created_at': _utc(series['created']),
    'folder_path': '',
    'issue_count': chapters.length,
    'cover_url': '/api/Image/series-cover?seriesId=$id',
    'publisher': _first(first, 'publishers'),
    'genres': [
      for (final g in (first['genres'] as List? ?? const []).cast<Map>()) g['title'],
    ],
    'description': first['summary'],
    'year': year != null && year > 1 ? year : null,
    'start_year': year != null && year > 1 ? year : null,
    'writer': _first(first, 'writers'),
    'penciller': _first(first, 'pencillers'),
    'issues': [
      for (final c in chapters)
        {
          'id': '${c['id']}',
          'name': _fileName(c),
          'number': number(c),
          'title': (c['titleName'] as String? ?? '').isNotEmpty
              ? c['titleName']
              : (c['isSpecial'] == true ? c['title'] : null),
          'summary': c['summary'],
          'cover_date': _utc(c['releaseDate'])?.substring(0, 10),
          'cover_url': '/api/Image/chapter-cover?chapterId=${c['id']}',
          'writer': _first(c, 'writers'),
          'penciller': _first(c, 'pencillers'),
        },
    ],
  };
}

/// A chapter's read progress in the `/sync` progress shape (0-based page;
/// finished reads as `current_page == total_pages`), or null when unread.
Map<String, dynamic>? kavitaProgress(Map<String, dynamic> chapter) {
  final read = chapter['pagesRead'] as int? ?? 0;
  if (read <= 0) return null;
  final total = chapter['pages'] as int? ?? 0;
  return {
    'comic_id': '${chapter['id']}',
    'current_page': read.clamp(0, total),
    'total_pages': total,
    'updated_at': _utc(chapter['lastReadingProgressUtc']),
  };
}
