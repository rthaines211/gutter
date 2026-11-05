import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/comic_file.dart';
import '../models/series.dart';
import '../models/comic_info.dart';
import '../models/reading_progress.dart';
import '../models/bookmark.dart';
import '../models/chapter.dart';
import '../models/reader_settings.dart';
import '../models/collection.dart';
import '../models/facet_value.dart';
import '../models/smart_filter.dart';
import '../models/reading_session.dart';
import '../models/stats_summary.dart';
import '../models/scan_status.dart';
import '../models/sync_response.dart';
import '../models/review_item.dart';
import '../models/reading_queue.dart';
import '../models/chapter_candidate.dart';
import '../models/template_rename_result.dart';
import '../models/creator.dart';
import '../models/creator_profile.dart';
import 'app_logger.dart';

typedef RequestOutcomeCallback = void Function(bool reachedServer);

class ApiException implements Exception {
  final int statusCode;
  final String message;

  ApiException(this.statusCode, this.message);

  @override
  String toString() => 'ApiException($statusCode): $message';
}

class ApiClient {
  final String baseUrl;
  final String deviceId;
  final http.Client _httpClient;
  final RequestOutcomeCallback? onRequestOutcome;

  /// The source's credentials, sent on every request.
  final Map<String, String> authHeaders;

  ApiClient({
    required this.baseUrl,
    required this.deviceId,
    http.Client? httpClient,
    this.onRequestOutcome,
    this.authHeaders = const {},
  }) : _httpClient = httpClient ?? http.Client();

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'X-Device-ID': deviceId,
        ...authHeaders,
      };

  Future<http.Response> _request({
    required String method,
    required String path,
    Object? body,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    final stopwatch = Stopwatch()..start();
    AppLogger.instance.http(
      level: LogLevel.debug,
      message: '$method start',
      context: {'method': method, 'url': uri.toString()},
    );
    try {
      late http.Response response;
      switch (method) {
        case 'GET':
          final req = http.Request('GET', uri)..headers.addAll(_headers);
          // One timeout over send + body: timing send() alone let a stalled
          // body hang forever, wedging the sync drain until relaunch.
          response = await _httpClient
              .send(req)
              .then(http.Response.fromStream)
              .timeout(timeout);
          break;
        case 'PUT':
          response = await _httpClient
              .put(uri, headers: _headers, body: jsonEncode(body))
              .timeout(timeout);
          break;
        case 'POST':
          response = await _httpClient
              .post(uri, headers: _headers, body: jsonEncode(body))
              .timeout(timeout);
          break;
        case 'DELETE':
          response = await _httpClient
              .delete(uri, headers: _headers)
              .timeout(timeout);
          break;
        case 'PATCH':
          final req = http.Request('PATCH', uri)
            ..headers.addAll(_headers)
            ..body = jsonEncode(body);
          // One timeout over send + body: timing send() alone let a stalled
          // body hang forever, wedging the sync drain until relaunch.
          response = await _httpClient
              .send(req)
              .then(http.Response.fromStream)
              .timeout(timeout);
          break;
        default:
          throw ArgumentError('Unsupported method: $method');
      }
      stopwatch.stop();
      final ok = response.statusCode >= 200 && response.statusCode < 300;
      AppLogger.instance.http(
        level: ok ? LogLevel.info : LogLevel.warn,
        message: '$method ${response.statusCode}',
        context: {
          'method': method,
          'url': uri.toString(),
          'status': response.statusCode,
          'durationMs': stopwatch.elapsedMilliseconds,
          if (!ok) 'body': _truncate(response.body, 500),
        },
      );
      _safeFireOutcome(true);
      return response;
    } catch (e) {
      if (e is SocketException ||
          e is TimeoutException ||
          e is HandshakeException ||
          e is http.ClientException) {
        _safeFireOutcome(false);
      }
      stopwatch.stop();
      AppLogger.instance.http(
        level: LogLevel.error,
        message: '$method failed',
        context: {
          'method': method,
          'url': uri.toString(),
          'durationMs': stopwatch.elapsedMilliseconds,
          'error': e.toString(),
          'errorType': e.runtimeType.toString(),
        },
      );
      rethrow;
    }
  }

  void _safeFireOutcome(bool reachedServer) {
    final cb = onRequestOutcome;
    if (cb == null) return;
    try {
      cb(reachedServer);
    } catch (_) {
      // Swallow caller-supplied callback errors — they must not affect
      // the HTTP request path or get logged as HTTP failures.
    }
  }

  static String _truncate(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max)}…';

  Future<dynamic> _get(String path,
      {Duration timeout = const Duration(seconds: 60)}) async {
    final response = await _request(
      method: 'GET',
      path: path,
      timeout: timeout,
    );
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return jsonDecode(response.body);
    }
    throw ApiException(response.statusCode, response.body);
  }

  Future<void> _put(String path, Map<String, dynamic> body) async {
    final response = await _request(method: 'PUT', path: path, body: body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, response.body);
    }
  }

  Future<dynamic> _postWithBody(String path, Map<String, dynamic> body) async {
    final response = await _request(method: 'POST', path: path, body: body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, response.body);
    }
    return jsonDecode(response.body);
  }

  Future<void> _delete(String path) async {
    final response = await _request(method: 'DELETE', path: path);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, response.body);
    }
  }

  Future<List<ComicFile>> browse({String path = ''}) async {
    final query = path.isNotEmpty ? '?path=${Uri.encodeComponent(path)}' : '';
    final data = await _get('/browse$query') as List<dynamic>;
    return data
        .map((e) => ComicFile.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<ComicFile>> search(String query) async {
    final data = await _get('/search?q=${Uri.encodeComponent(query)}') as List<dynamic>;
    return data
        .map((e) => ComicFile.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static void _validateRenameName(String name) {
    if (name.isEmpty) throw ArgumentError('Name must not be empty');
    if (name.contains('/') || name.contains('\\') || name.contains('..')) {
      throw ArgumentError('Name must not contain path separators or "..": $name');
    }
    if (name.contains('\x00')) throw ArgumentError('Name must not contain null bytes');
  }

  Future<ComicInfo> getComicInfo(String comicId) async {
    final data = await _get('/comics/${Uri.encodeComponent(comicId)}/info');
    return ComicInfo.fromJson(data as Map<String, dynamic>);
  }

  String pageUrl(String comicId, int pageNum) =>
      '$baseUrl/comics/${Uri.encodeComponent(comicId)}/pages/$pageNum';

  /// Bubble-zoom sidecar for a page, or null when the host job hasn't processed it (404).
  Future<Map<String, dynamic>?> getPageBubbles(String comicId, int page) async {
    try {
      return await _get('/comics/${Uri.encodeComponent(comicId)}/pages/$page/bubbles',
          timeout: const Duration(seconds: 15)) as Map<String, dynamic>;
    } on ApiException catch (e) {
      if (e.statusCode == 404) {
        return null;
      }
      rethrow;
    }
  }

  Future<void> putBubbleOrder(String comicId, int page, List<int> labels) =>
      _put('/comics/${Uri.encodeComponent(comicId)}/pages/$page/bubbles/order', {'labels': labels});

  /// Marks a page whose panels or balloons came out wrong, for the
  /// detector's labelling set. [reason] is one offered in [zoom] mode
  /// (see flagReasons).
  Future<void> flagPage(String comicId, int page, {required String reason, required String zoom}) =>
      _put('/comics/${Uri.encodeComponent(comicId)}/pages/$page/flag', {'reason': reason, 'zoom': zoom});

  String coverUrl(String comicId) => '$baseUrl/comics/${Uri.encodeComponent(comicId)}/cover';

  Future<List<ReadingProgress>> getReadingList() async {
    final data = await _get('/reading') as Map<String, dynamic>;
    final inProgress = data['in_progress'] as List<dynamic>? ?? [];
    return inProgress
        .map((e) => ReadingProgress.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> updateProgress({
    required String comicId,
    required int currentPage,
    required int totalPages,
    List<Bookmark>? bookmarks,
    List<Chapter>? chapters,
    int? readAtMs,
  }) async {
    final body = <String, dynamic>{
      'current_page': currentPage,
      'total_pages': totalPages,
      'bookmarks': (bookmarks ?? []).map((b) => b.toJson()).toList(),
      'read_at': readAtMs ?? DateTime.now().millisecondsSinceEpoch,
    };
    // Only send chapters when explicitly provided. Omitting the field tells the
    // backend to leave the chapter set untouched, so a routine progress save
    // never wipes chapters written out-of-band (or by a chapter mutation).
    if (chapters != null) {
      body['chapters'] = chapters.map((c) => c.toJson()).toList();
    }
    await _put('/reading/${Uri.encodeComponent(comicId)}', body);
  }

  Future<ReaderSettings> getSettings() async {
    final data = await _get('/settings');
    return ReaderSettings.fromJson(data as Map<String, dynamic>);
  }

  Future<void> updateSettings(ReaderSettings settings) async {
    await _put('/settings', settings.toJson());
  }

  Future<List<Series>> fetchLibrary({
    String sort = 'name',
    String order = 'asc',
    String status = 'all',
    String? query,
    String? publisher,
    String? genre,
    String? writer,
    String? penciller,
    int? yearMin,
    int? yearMax,
  }) async {
    final params = <String, String>{
      'sort': sort,
      'order': order,
    };
    if (status != 'all') params['status'] = status;
    if (query != null && query.isNotEmpty) params['q'] = query;
    if (publisher != null) params['publisher'] = publisher;
    if (genre != null) params['genre'] = genre;
    if (writer != null) params['writer'] = writer;
    if (penciller != null) params['penciller'] = penciller;
    if (yearMin != null) params['year_min'] = yearMin.toString();
    if (yearMax != null) params['year_max'] = yearMax.toString();

    final queryString = params.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');
    final data = await _get('/library?$queryString') as List<dynamic>;
    return data
        .map((e) => Series.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Delta sync: everything changed since the given server watermark
  /// (unix milliseconds; 0 = full sync).
  Future<SyncResponse> fetchSync({required int since}) async {
    // The first sync of a fresh mirror is `since=0`: every series with inline
    // issues in one payload, which can take well over the default 60s on a
    // large library. Incremental syncs (since>0) return quickly, so the long
    // ceiling only ever applies to the one-time bootstrap.
    final data = await _get('/sync?since=$since',
        timeout: const Duration(minutes: 4)) as Map<String, dynamic>;
    return SyncResponse.fromJson(data);
  }

  Future<SeriesDetail> fetchSeriesDetail(String seriesId) async {
    final data = await _get('/library/${Uri.encodeComponent(seriesId)}');
    return SeriesDetail.fromJson(data as Map<String, dynamic>);
  }

  Future<List<CreatorSummary>> fetchCreators() async {
    final data = await _get('/creators') as List<dynamic>;
    return data
        .map((e) => CreatorSummary.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Full creator profile, or null when the creator id is unknown (404).
  Future<CreatorProfile?> fetchCreator(int id) async {
    try {
      final data = await _get('/creators/$id');
      return CreatorProfile.fromJson(data as Map<String, dynamic>);
    } on ApiException catch (e) {
      if (e.statusCode == 404) {
        return null;
      }
      rethrow;
    }
  }

  Future<List<PersonMatch>> lookupCreator(String name) async {
    final data = await _get('/creators/lookup?name=${Uri.encodeComponent(name)}')
        as List<dynamic>;
    return data
        .map((e) => PersonMatch.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<VolumeInfo> fetchVolumeInfo(int id) async {
    final data = await _get('/creators/volumes/$id');
    return VolumeInfo.fromJson(data as Map<String, dynamic>);
  }

  /// Issue-level creator credits, or null when the comic has no ComicVine
  /// id (404).
  Future<List<Creator>?> fetchIssueCredits(String comicId) async {
    try {
      final data =
          await _get('/creators/issues/${Uri.encodeComponent(comicId)}') as List<dynamic>;
      return data.map((e) => Creator.fromJson(e as Map<String, dynamic>)).toList();
    } on ApiException catch (e) {
      if (e.statusCode == 404) {
        return null;
      }
      rethrow;
    }
  }

  /// Raw series JSON (issues inline) — same element shape as a `/sync` series
  /// entry. Used by the mirror self-heal to backfill a series that's on the
  /// server keep-list but missing from the local mirror.
  Future<Map<String, dynamic>> fetchSeriesRaw(String seriesId) async {
    final data = await _get('/library/${Uri.encodeComponent(seriesId)}');
    return data as Map<String, dynamic>;
  }

  /// Triggers an async library rescan.
  /// Returns true if scan was started, false if one is already running.
  Future<bool> refreshLibrary() async {
    final uri = Uri.parse('$baseUrl/library/refresh');
    final response = await _httpClient
        .post(uri, headers: _headers)
        .timeout(const Duration(seconds: 30));
    if (response.statusCode == 409) {
      return false; // scan already in progress
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, response.body);
    }
    return true;
  }

  Future<ScanStatus> getScanStatus() async {
    final data = await _get('/library/refresh/status');
    return ScanStatus.fromJson(data as Map<String, dynamic>);
  }

  /// Renames a comic file on disk. Returns the new comic ID and filename.
  Future<Map<String, String>> renameComic(String comicId, String newName) async {
    _validateRenameName(newName);
    final uri = Uri.parse('$baseUrl/comics/${Uri.encodeComponent(comicId)}/rename');
    final response = await _httpClient.put(
      uri,
      headers: _headers,
      body: jsonEncode({'name': newName}),
    ).timeout(const Duration(seconds: 30));
    if (response.statusCode == 409) {
      throw ApiException(409, 'A file with that name already exists');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, response.body);
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return {
      'id': data['id'] as String,
      'name': data['name'] as String,
    };
  }

  Future<List<FacetValue>> fetchFacet(
    String facet, {
    String status = 'all',
    String? publisher,
    String? genre,
    String? writer,
    String? penciller,
    int? yearMin,
    int? yearMax,
  }) async {
    final params = <String, String>{};
    if (status != 'all') params['status'] = status;
    if (publisher != null) params['publisher'] = publisher;
    if (genre != null) params['genre'] = genre;
    if (writer != null) params['writer'] = writer;
    if (penciller != null) params['penciller'] = penciller;
    if (yearMin != null) params['year_min'] = yearMin.toString();
    if (yearMax != null) params['year_max'] = yearMax.toString();

    var path = '/facets/${Uri.encodeComponent(facet)}';
    if (params.isNotEmpty) {
      final queryString = params.entries
          .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
          .join('&');
      path += '?$queryString';
    }
    final data = await _get(path) as List<dynamic>;
    return data
        .map((e) => FacetValue.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // Smart Filters
  Future<List<SmartFilter>> fetchSmartFilters() async {
    final data = await _get('/smart-filters') as List<dynamic>;
    return data
        .map((e) => SmartFilter.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<int> createSmartFilter(SmartFilter filter) async {
    final data = await _postWithBody('/smart-filters', filter.toCreateJson());
    return (data as Map<String, dynamic>)['id'] as int;
  }

  Future<void> updateSmartFilter(int id, SmartFilter filter) async {
    await _put('/smart-filters/$id', filter.toCreateJson());
  }

  Future<void> deleteSmartFilter(int id) async {
    await _delete('/smart-filters/$id');
  }

  Future<List<Series>> fetchSmartFilterSeries(int id) async {
    final data = await _get('/smart-filters/$id/series') as List<dynamic>;
    return data
        .map((e) => Series.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<bool> checkConnection() async {
    final stopwatch = Stopwatch()..start();
    try {
      final response = await _request(
        method: 'GET',
        path: '/browse',
        timeout: const Duration(seconds: 5),
      );
      stopwatch.stop();
      final ok = response.statusCode >= 200 && response.statusCode < 300;
      AppLogger.instance.connectivity(
        level: ok ? LogLevel.debug : LogLevel.warn,
        message: 'health check ${response.statusCode}',
        context: {
          'url': '$baseUrl/browse',
          'status': response.statusCode,
          'durationMs': stopwatch.elapsedMilliseconds,
        },
      );
      return ok;
    } catch (e) {
      stopwatch.stop();
      AppLogger.instance.connectivity(
        level: LogLevel.warn,
        message: 'health check failed',
        context: {
          'url': '$baseUrl/browse',
          'durationMs': stopwatch.elapsedMilliseconds,
          'error': e.toString(),
        },
      );
      return false;
    }
  }

  String seriesCoverUrl(String seriesId) => '$baseUrl/library/${Uri.encodeComponent(seriesId)}/cover';

  // Collections
  Future<List<Collection>> fetchCollections() async {
    final data = await _get('/collections') as List<dynamic>;
    return data
        .map((e) => Collection.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<int> createCollection({
    required String name,
    String icon = 'bookmark',
    String color = '#FFB74D',
  }) async {
    final data = await _postWithBody('/collections', {
      'name': name,
      'icon': icon,
      'color': color,
    });
    return (data as Map<String, dynamic>)['id'] as int;
  }

  Future<void> updateCollection({
    required int id,
    required String name,
    required String icon,
    required String color,
  }) async {
    await _put('/collections/$id', {
      'name': name,
      'icon': icon,
      'color': color,
    });
  }

  Future<void> deleteCollection(int id) async {
    await _delete('/collections/$id');
  }

  Future<void> addSeriesToCollection(int collectionId, String seriesId) async {
    await _postWithBody('/collections/$collectionId/series', {
      'series_id': seriesId,
    });
  }

  Future<void> removeSeriesFromCollection(int collectionId, String seriesId) async {
    await _delete('/collections/$collectionId/series/$seriesId');
  }

  Future<void> reorderCollectionSeries(int collectionId, List<String> seriesIds) async {
    await _put('/collections/$collectionId/series', {
      'series_ids': seriesIds,
    });
  }

  // Reading Queues (snapshot upsert; id is client-generated)
  Future<void> putQueue(ReadingQueue queue) async {
    await _put('/queues/${Uri.encodeComponent(queue.id)}', {
      'name': queue.name,
      'icon': queue.icon,
      'color': queue.color,
      'position': queue.position,
      'series_ids': queue.seriesIds,
    });
  }

  Future<void> deleteQueue(String id) async {
    await _delete('/queues/${Uri.encodeComponent(id)}');
  }

  // Batch reading progress
  Future<void> batchUpdateProgress(List<Map<String, dynamic>> items) async {
    await _put('/reading/batch', {'items': items});
  }

  Future<void> batchDeleteProgress(List<String> comicIds) async {
    final uri = Uri.parse('$baseUrl/reading/batch');
    final request = http.Request('DELETE', uri);
    request.headers.addAll(_headers);
    request.body = jsonEncode({'comic_ids': comicIds});
    final response = await _httpClient
        .send(request)
        .then(http.Response.fromStream)
        .timeout(const Duration(seconds: 30));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, response.body);
    }
  }

  Future<void> postReadingSession({
    required String comicId,
    required String seriesId,
    required DateTime startedAt,
    required int pagesRead,
    required int durationS,
  }) async {
    await _postWithBody('/reading/sessions', {
      'comic_id': comicId,
      'series_id': seriesId,
      'started_at': startedAt.toUtc().toIso8601String(),
      'pages_read': pagesRead,
      'duration_s': durationS,
    });
  }

  Future<StatsSummary> fetchStatsSummary() async {
    final data = await _get('/stats/summary');
    return StatsSummary.fromJson(data as Map<String, dynamic>);
  }

  Future<({List<ReadingSession> sessions, int total})> fetchStatsHistory({
    int page = 1,
    int limit = 20,
  }) async {
    final data = await _get('/stats/history?page=$page&limit=$limit');
    final map = data as Map<String, dynamic>;
    final sessions = (map['sessions'] as List<dynamic>)
        .map((e) => ReadingSession.fromJson(e as Map<String, dynamic>))
        .toList();
    return (sessions: sessions, total: map['total'] as int);
  }

  Future<({int count, List<ReviewItem> items})> fetchReviewQueue() async {
    final map = await _get('/review') as Map<String, dynamic>;
    final items = (map['items'] as List<dynamic>? ?? [])
        .map((e) => ReviewItem.fromJson(e as Map<String, dynamic>))
        .toList();
    return (count: map['count'] as int? ?? items.length, items: items);
  }

  Future<List<VolumeHit>> searchReviewVolumes(String query) async {
    if (query.trim().isEmpty) return [];
    final data =
        await _get('/review/search?q=${Uri.encodeQueryComponent(query.trim())}')
            as List<dynamic>;
    return data
        .map((e) => VolumeHit.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> confirmReview(String seriesId) =>
      _postNoContent('/review/${Uri.encodeComponent(seriesId)}/confirm');

  Future<void> pinReviewVolume(String seriesId, VolumeHit hit) =>
      _postNoContent('/review/${Uri.encodeComponent(seriesId)}/volume',
          {'source': hit.source, 'volume_id': hit.volumeId});

  Future<void> dontMatchReview(String seriesId) =>
      _postNoContent('/review/${Uri.encodeComponent(seriesId)}/dont-match');

  // 204 responses have no body, so _postWithBody's jsonDecode can't be used.
  Future<void> _postNoContent(String path,
      [Map<String, dynamic> body = const {}]) async {
    final response = await _request(method: 'POST', path: path, body: body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, response.body);
    }
  }

  Future<({List<ChapterCandidate> candidates, bool ocrPending, String? jobId})>
      detectChapters(
    String comicId, {
    int? exemplarPage,
  }) async {
    final body = <String, dynamic>{};
    if (exemplarPage != null) body['exemplarPage'] = exemplarPage;
    final data = await _postWithBody(
      '/comics/${Uri.encodeComponent(comicId)}/detect-chapters',
      body,
    ) as Map<String, dynamic>;
    final list = (data['candidates'] as List<dynamic>? ?? [])
        .map((e) => ChapterCandidate.fromJson(e as Map<String, dynamic>))
        .toList();
    return (
      candidates: list,
      ocrPending: data['ocrPending'] as bool? ?? false,
      jobId: data['jobId'] as String?,
    );
  }

  Future<({String state, int scanned, int total, List<ChapterCandidate> candidates})>
      detectChaptersStatus(String comicId, String jobId) async {
    final data = await _get(
      '/comics/${Uri.encodeComponent(comicId)}/detect-chapters/status?job=$jobId',
    ) as Map<String, dynamic>;
    final list = (data['candidates'] as List<dynamic>? ?? [])
        .map((e) => ChapterCandidate.fromJson(e as Map<String, dynamic>))
        .toList();
    // Prefer explicit state; fall back to legacy done:bool for older servers.
    final state = (data['state'] as String?) ??
        ((data['done'] as bool? ?? false) ? 'done' : 'running');
    return (
      state: state,
      scanned: data['scanned'] as int? ?? 0,
      total: data['total'] as int? ?? 0,
      candidates: list,
    );
  }

  // ── Metadata editing ────────────────────────────────────────────────────────

  Future<void> patchComicMetadata(
      String comicId, Map<String, dynamic> fields) async {
    final response = await _request(
      method: 'PATCH',
      path: '/comics/${Uri.encodeComponent(comicId)}/metadata',
      body: fields,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, response.body);
    }
  }

  Future<void> patchSeriesMetadata(
      String seriesId, Map<String, dynamic> fields) async {
    final response = await _request(
      method: 'PATCH',
      path: '/series/${Uri.encodeComponent(seriesId)}/metadata',
      body: fields,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, response.body);
    }
  }

  /// Renames a series folder on disk. Returns the new series id and name.
  /// Throws [ApiException] with statusCode 409 if a folder with that name
  /// already exists (mirrors [renameComic] behaviour).
  Future<Map<String, String>> renameSeriesFolder(
      String seriesId, String newName) async {
    final response = await _request(
      method: 'PUT',
      path: '/series/${Uri.encodeComponent(seriesId)}/rename-folder',
      body: {'name': newName},
    );
    if (response.statusCode == 409) {
      throw ApiException(409, 'A folder with that name already exists');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, response.body);
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return {
      'id': (data['id'] as String?) ?? '',
      'name': (data['name'] as String?) ?? '',
    };
  }

  Future<List<TemplateRenameResult>> applyTemplate(
    String seriesId, {
    required bool dryRun,
  }) async {
    final query = dryRun ? '?dry_run=1' : '';
    final response = await _request(
      method: 'POST',
      path: '/series/${Uri.encodeComponent(seriesId)}/apply-template$query',
      body: const <String, dynamic>{},
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, response.body);
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return (data['results'] as List<dynamic>)
        .map((e) => TemplateRenameResult.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, String>> fetchRenameTemplates() async {
    final data =
        await _get('/rename-templates') as Map<String, dynamic>;
    return (data['templates'] as Map<String, dynamic>)
        .map((k, v) => MapEntry(k, v as String));
  }

  Future<void> saveRenameTemplates(Map<String, String> templates) async {
    await _put('/rename-templates', {'templates': templates});
  }
}
