import 'dart:io';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'local_pages.dart';

/// Adds the active source's credentials to requests for that source's URLs
/// (same scheme, host, port and base path), and to nothing else. Image
/// loads (covers, pages, prefetch) and cover sync go through it, so no
/// widget has to pass headers.
class SourceAuthClient extends http.BaseClient {
  SourceAuthClient([http.Client? inner]) : _inner = inner ?? http.Client();
  final http.Client _inner;

  static Uri? _base;
  static Map<String, String> _headers = const {};

  /// Called whenever the active source (or its loaded credentials) changes.
  /// [localDir] is a local source's library (`<docs>/downloads/<sourceId>`).
  static void use(String baseUrl, Map<String, String> headers,
      {String? localDir}) {
    _base = baseUrl.isEmpty ? null : Uri.parse(baseUrl);
    _headers = headers;
    _localDir = localDir;
  }

  static String? _localDir;

  /// A local source has no server: its `local:/comics/<id>/cover` and
  /// `local:/comics/<id>/pages/<n>` URLs are the imported page files, so
  /// every cover widget works unchanged.
  /// ponytail: the image cache keeps a second copy of each cover it shows.
  static http.StreamedResponse _local(http.BaseRequest request) {
    final seg = request.url.pathSegments;
    final dir = _localDir;
    File? file;
    if (dir != null &&
        seg.length >= 3 &&
        seg[0] == 'comics' &&
        p.basename(seg[1]) == seg[1] &&
        seg[1] != '..') {
      final page = seg[2] == 'cover'
          ? 0
          : (seg[2] == 'pages' && seg.length == 4 ? int.tryParse(seg[3]) : null);
      if (page != null) {
        file = localPageFile(p.join(dir, seg[1], 'pages'), page);
      }
    }
    if (file == null || !file.existsSync()) {
      return http.StreamedResponse(const Stream.empty(), 404, request: request);
    }
    final ext = p.extension(file.path).toLowerCase().replaceFirst('.', '');
    return http.StreamedResponse(file.openRead(), 200,
        request: request,
        contentLength: file.lengthSync(),
        headers: {'content-type': 'image/${ext == 'jpg' ? 'jpeg' : ext}'});
  }

  static bool _ownedBySource(Uri url) {
    final base = _base;
    if (base == null) return false;
    final basePath = base.path.endsWith('/') ? base.path : '${base.path}/';
    return url.scheme == base.scheme &&
        url.host == base.host &&
        url.port == base.port &&
        (url.path == base.path || url.path.startsWith(basePath));
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (request.url.scheme == 'local') return Future.value(_local(request));
    if (_headers.isNotEmpty && _ownedBySource(request.url)) {
      request.headers.addAll(_headers);
    }
    return _inner.send(request);
  }
}

/// The app-wide image cache (same store as the package default), fetching
/// through [SourceAuthClient].
class SourceImageCacheManager extends CacheManager with ImageCacheManager {
  SourceImageCacheManager()
      : super(Config(DefaultCacheManager.key,
            fileService: HttpFileService(httpClient: SourceAuthClient())));
}
