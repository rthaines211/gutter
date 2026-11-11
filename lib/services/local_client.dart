import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../models/bookmark.dart';
import '../models/chapter.dart';
import '../models/comic_info.dart';
import '../models/creator.dart';
import '../models/series.dart';
import '../models/server_source.dart';
import '../models/sync_response.dart';
import 'api_client.dart';
import 'komga_client.dart' show LocalReaderData;
import 'local_import.dart' show compareNatural;
import 'local_session_store.dart';

/// The "On this device" source: no server. The library is whatever
/// [importCbz] put under [libraryDir] (`<docs>/downloads/<sourceId>`), read
/// from each comic's `metadata.json`; progress lives only in the mirror.
class LocalClient extends ApiClient with LocalReaderData {
  LocalClient({
    required this.libraryDir,
    required super.deviceId,
    super.onRequestOutcome,
    this.sessions,
  }) : super(baseUrl: localBaseUrl, httpClient: _NoServer());

  /// Null until the documents directory is known.
  final String? libraryDir;

  @override
  final LocalSessionStore? sessions;

  /// Every imported comic's metadata.json.
  Future<List<Map<String, dynamic>>> _comics() async {
    final dir = libraryDir;
    if (dir == null) throw StateError('Documents directory not ready');
    final comics = <Map<String, dynamic>>[];
    if (!await Directory(dir).exists()) return comics;
    await for (final d in Directory(dir).list()) {
      try {
        comics.add(jsonDecode(
                await File(p.join(d.path, 'metadata.json')).readAsString())
            as Map<String, dynamic>);
      } catch (_) {
        // Not a finished import.
      }
    }
    return comics;
  }

  /// [comics] as `/sync`-shaped series with issues inline, in reading order.
  static List<Map<String, dynamic>> _series(List<Map<String, dynamic>> comics) {
    final bySeries = <String, List<Map<String, dynamic>>>{};
    for (final c in comics) {
      bySeries.putIfAbsent(c['series_id'] as String, () => []).add(c);
    }
    num? n(Map<String, dynamic> c) => num.tryParse(c['number'] as String? ?? '');
    String name(Map<String, dynamic> c) => c['comic_name'] as String? ?? '';
    return [
      for (final e in bySeries.entries)
        () {
          final issues = e.value
            ..sort((a, b) {
              final x = n(a), y = n(b);
              final c = x != null && y != null ? x.compareTo(y) : 0;
              return c != 0 ? c : compareNatural(name(a), name(b));
            });
          final stamps = [for (final i in issues) i['downloaded_at'] as String? ?? '']
            ..sort();
          return <String, dynamic>{
            'id': e.key,
            'name': issues.first['series_name'] ?? '',
            'updated_at': stamps.last,
            'created_at': stamps.first,
            'folder_path': '',
            'issue_count': issues.length,
            // `local:` URLs are answered from the page files by
            // SourceAuthClient: the series cover is its first issue's.
            'cover_url': '/comics/${issues.first['comic_id']}/cover',
            'genres': const [],
            'issues': [
              for (final i in issues)
                {
                  'id': i['comic_id'],
                  'name': name(i),
                  'number': i['number'],
                  'cover_url': '/comics/${i['comic_id']}/cover',
                  'total_pages': i['page_count'],
                },
            ],
          };
        }(),
    ];
  }

  /// Disk is the truth: a deleted comic drops out of `series_ids` and the
  /// mirror prunes it. `progress` is empty and `progress_ids` lists every
  /// comic, so the mirror keeps the progress it has for comics still here
  /// and prunes it for deleted ones.
  @override
  Future<SyncResponse> fetchSync(
      {required int since, void Function(int done, int total)? onSeries}) async {
    final comics = await _comics();
    final series = _series(comics);
    return SyncResponse(
      serverTime: DateTime.now().millisecondsSinceEpoch,
      series: series,
      progress: const [],
      seriesIds: [for (final s in series) s['id'] as String],
      progressIds: [for (final c in comics) c['comic_id'] as String],
      serverHasQueues: false,
    );
  }

  @override
  Future<Map<String, dynamic>> fetchSeriesRaw(String seriesId) async =>
      _series(await _comics()).firstWhere((s) => s['id'] == seriesId,
          orElse: () => throw ApiException(404, 'No such series'));

  @override
  Future<SeriesDetail> fetchSeriesDetail(String seriesId) async =>
      SeriesDetail.fromJson(await fetchSeriesRaw(seriesId));

  @override
  Future<ComicInfo> getComicInfo(String comicId) async {
    final c = (await _comics()).firstWhere((c) => c['comic_id'] == comicId,
        orElse: () => throw ApiException(404, 'No such comic'));
    return ComicInfo(
      title: c['comic_name'] as String? ?? '',
      series: c['series_name'] as String?,
      number: c['number'] as String?,
      pageCount: c['page_count'] as int? ?? 0,
    );
  }

  @override
  Future<void> updateProgress({
    required String comicId,
    required int currentPage,
    required int totalPages,
    List<Bookmark>? bookmarks,
    List<Chapter>? chapters,
    int? readAtMs,
  }) async {}

  @override
  Future<void> batchUpdateProgress(List<Map<String, dynamic>> items) async {}

  @override
  Future<void> batchDeleteProgress(List<String> comicIds) async {}

  @override
  Future<List<Creator>?> fetchIssueCredits(String comicId) async => null;

  /// Always reachable: there is no server to lose.
  @override
  Future<int?> probeStatus() async {
    onRequestOutcome?.call(true);
    return 200;
  }
}

/// Answers every request 404 without touching the network, so a call this
/// client doesn't override fails as "not found", never as "offline".
class _NoServer extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(Stream.value(utf8.encode('{"error":"no server"}')), 404,
          request: request);
}
