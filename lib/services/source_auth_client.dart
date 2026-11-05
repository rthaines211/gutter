import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;

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
  static void use(String baseUrl, Map<String, String> headers) {
    _base = baseUrl.isEmpty ? null : Uri.parse(baseUrl);
    _headers = headers;
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
