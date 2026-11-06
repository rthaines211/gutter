import '../models/comic_info.dart';
import '../models/bookmark.dart';
import '../models/chapter.dart';
import '../models/reader_settings.dart';
import '../models/reading_queue.dart';
import '../models/reading_session.dart';
import '../models/stats_summary.dart';
import '../models/series.dart';
import '../models/sync_response.dart';
import 'api_client.dart';
import 'local_session_store.dart';
import 'local_stats.dart';

/// A Komga server behind the [ApiClient] surface the mirror, reader and
/// progress sync use. Everything else the app calls is Gutter-server only
/// and hidden on Komga sources (`isCustomSourceProvider`).
class KomgaClient extends ApiClient {
  KomgaClient({
    required super.baseUrl,
    required super.deviceId,
    super.httpClient,
    super.onRequestOutcome,
    super.authHeaders,
    this.sessions,
  });

  /// Where reading sessions go (Komga has no session API); stats come
  /// from here.
  final LocalSessionStore? sessions;

  static String _enc(String id) => Uri.encodeComponent(id);

  Future<List<Map<String, dynamic>>> _books([Map<String, dynamic>? condition]) async {
    final data = await requestJson(
        'POST', '/api/v1/books/list?unpaged=true',
        body: {'condition': ?condition},
        timeout: const Duration(minutes: 4)) as Map<String, dynamic>;
    return (data['content'] as List<dynamic>).cast<Map<String, dynamic>>();
  }

  // ponytail: full pull every sync (Komga has no lastModified search
  // condition); page books by sort=lastModified,desc if big libraries get slow.
  @override
  Future<SyncResponse> fetchSync({required int since}) async {
    final data = await requestJson('POST', '/api/v1/series/list?unpaged=true',
        body: {}, timeout: const Duration(minutes: 4)) as Map<String, dynamic>;
    final series = (data['content'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .where((s) => s['deleted'] != true)
        .toList();
    final books = await _books();
    final bySeries = <String, List<Map<String, dynamic>>>{};
    for (final b in books) {
      bySeries.putIfAbsent(b['seriesId'] as String, () => []).add(b);
    }
    final progress = [
      for (final b in books)
        if (_readable(b)) ?komgaProgress(b),
    ];
    return SyncResponse(
      serverTime: DateTime.now().millisecondsSinceEpoch,
      series: [
        for (final s in series)
          komgaSeriesToSync(s, bySeries[s['id']] ?? const []),
      ],
      progress: progress,
      seriesIds: [for (final s in series) s['id'] as String],
      progressIds: [for (final p in progress) p['comic_id'] as String],
      serverHasQueues: false,
    );
  }

  @override
  Future<Map<String, dynamic>> fetchSeriesRaw(String seriesId) async {
    final s = await requestJson('GET', '/api/v1/series/${_enc(seriesId)}')
        as Map<String, dynamic>;
    final books = await _books({
      'seriesId': {'operator': 'is', 'value': seriesId},
    });
    final map = komgaSeriesToSync(s, books);
    // Issue statuses inline, as GET /library/{id} returns them.
    final progress = {
      for (final b in books)
        b['id']: ?komgaProgress(b),
    };
    for (final i in (map['issues'] as List).cast<Map<String, dynamic>>()) {
      final p = progress[i['id']];
      if (p == null) continue;
      final cp = p['current_page'] as int, tp = p['total_pages'] as int;
      i['current_page'] = cp;
      i['total_pages'] = tp;
      i['status'] = tp > 0 && cp >= tp ? 'completed' : 'in_progress';
    }
    return map;
  }

  @override
  Future<SeriesDetail> fetchSeriesDetail(String seriesId) async =>
      SeriesDetail.fromJson(await fetchSeriesRaw(seriesId));

  @override
  Future<ComicInfo> getComicInfo(String comicId) async {
    final b = await requestJson('GET', '/api/v1/books/${_enc(comicId)}')
        as Map<String, dynamic>;
    final meta = b['metadata'] as Map<String, dynamic>? ?? const {};
    return ComicInfo(
      title: meta['title'] as String? ?? b['name'] as String? ?? '',
      series: b['seriesTitle'] as String?,
      number: meta['number'] as String?,
      summary: meta['summary'] as String?,
      pageCount: _pages(b),
    );
  }

  @override
  String pageUrl(String comicId, int pageNum) =>
      '$baseUrl/api/v1/books/${_enc(comicId)}/pages/${pageNum + 1}';

  @override
  Future<void> updateProgress({
    required String comicId,
    required int currentPage,
    required int totalPages,
    List<Bookmark>? bookmarks,
    List<Chapter>? chapters,
    int? readAtMs,
  }) async {
    await requestJson('PATCH', '/api/v1/books/${_enc(comicId)}/read-progress',
        body: currentPage >= totalPages
            ? {'completed': true}
            : {'page': currentPage + 1});
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

  @override
  Future<void> batchDeleteProgress(List<String> comicIds) async {
    for (final id in comicIds) {
      await requestJson('DELETE', '/api/v1/books/${_enc(id)}/read-progress');
    }
  }

  @override
  Future<int?> probeStatus() async {
    try {
      await requestJson('GET', '/api/v2/users/me',
          timeout: const Duration(seconds: 5));
      return 200;
    } on ApiException catch (e) {
      return e.statusCode;
    } catch (_) {
      return null;
    }
  }

  /// Komga keeps no reader settings: settingsProvider falls back to its
  /// local cache.
  @override
  Future<ReaderSettings> getSettings() =>
      Future.error(UnsupportedError('Komga has no reader settings'));

  @override
  Future<void> updateSettings(ReaderSettings settings) async {}

  @override
  Future<void> postReadingSession({
    required String comicId,
    required String seriesId,
    required DateTime startedAt,
    required int pagesRead,
    required int durationS,
  }) async {
    await sessions?.append(LocalSession(
      comicId: comicId,
      seriesId: seriesId,
      startedAt: startedAt,
      pagesRead: pagesRead,
      durationS: durationS,
    ));
  }

  /// Without series names; the Stats screen adds them from the mirror.
  @override
  Future<StatsSummary> fetchStatsSummary() async =>
      computeLocalStats(await sessions?.all() ?? const [], const {}, DateTime.now());

  @override
  Future<({List<ReadingSession> sessions, int total})> fetchStatsHistory({
    int page = 1,
    int limit = 20,
  }) async =>
      localHistory(await sessions?.all() ?? const [], const {},
          page: page, limit: limit);

  @override
  Future<void> putQueue(ReadingQueue queue) async {}

  @override
  Future<void> deleteQueue(String id) async {}
}

int _pages(Map<String, dynamic> book) =>
    (book['media'] as Map<String, dynamic>?)?['pagesCount'] as int? ?? 0;

bool _readable(Map<String, dynamic> book) =>
    book['deleted'] != true &&
    (book['media'] as Map<String, dynamic>?)?['status'] == 'READY' &&
    _pages(book) > 0;

String? _author(List<dynamic>? authors, String role) {
  for (final a in authors ?? const []) {
    if ((a as Map<String, dynamic>)['role'] == role) return a['name'] as String?;
  }
  return null;
}

int? _year(String? date) =>
    date == null || date.length < 4 ? null : int.tryParse(date.substring(0, 4));

/// A Komga series and its books in the Gutter `/sync` series shape, with
/// readable issues inline in reading order.
Map<String, dynamic> komgaSeriesToSync(
    Map<String, dynamic> series, List<Map<String, dynamic>> books) {
  final id = series['id'] as String;
  final meta = series['metadata'] as Map<String, dynamic>? ?? const {};
  final agg = series['booksMetadata'] as Map<String, dynamic>? ?? const {};
  final summary = meta['summary'] as String?;
  final year = _year(agg['releaseDate'] as String?);
  num sort(Map<String, dynamic> b) =>
      (b['metadata'] as Map<String, dynamic>?)?['numberSort'] as num? ?? 0;
  final readable = books.where(_readable).toList()
    ..sort((a, b) => sort(a).compareTo(sort(b)));
  return {
    'id': id,
    'name': meta['title'] as String? ?? series['name'] as String? ?? '',
    'updated_at': series['lastModified'],
    'created_at': series['created'],
    'folder_path': '',
    'issue_count': readable.length,
    'cover_url': '/api/v1/series/${Uri.encodeComponent(id)}/thumbnail',
    'publisher': meta['publisher'],
    'genres': meta['genres'] ?? const [],
    'description': (summary == null || summary.isEmpty) ? agg['summary'] : summary,
    'year': year,
    'start_year': year,
    'writer': _author(agg['authors'] as List?, 'writer'),
    'penciller': _author(agg['authors'] as List?, 'penciller'),
    'issues': [
      for (final b in readable)
        {
          'id': b['id'],
          'name': b['name'],
          'number': (b['metadata'] as Map?)?['number'],
          'title': (b['metadata'] as Map?)?['title'],
          'summary': (b['metadata'] as Map?)?['summary'],
          'cover_date': (b['metadata'] as Map?)?['releaseDate'],
          'cover_url': '/api/v1/books/${Uri.encodeComponent(b['id'] as String)}/thumbnail',
          'writer': _author((b['metadata'] as Map?)?['authors'] as List?, 'writer'),
          'penciller': _author((b['metadata'] as Map?)?['authors'] as List?, 'penciller'),
        },
    ],
  };
}

/// A book's read progress in the `/sync` progress shape (0-based page;
/// completed reads as `current_page == total_pages`), or null when unread.
Map<String, dynamic>? komgaProgress(Map<String, dynamic> book) {
  final rp = book['readProgress'] as Map<String, dynamic>?;
  if (rp == null) return null;
  final total = _pages(book);
  final page = rp['page'] as int? ?? 1;
  return {
    'comic_id': book['id'],
    'current_page': rp['completed'] == true ? total : (page - 1).clamp(0, total),
    'total_pages': total,
    'updated_at': rp['lastModified'],
  };
}
