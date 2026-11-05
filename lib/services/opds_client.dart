import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';
import '../models/server_source.dart';

/// A parsed OPDS feed.
class OPDSFeed {
  final String title;
  final String id;
  final List<OPDSEntry> entries;
  final String? nextUrl;
  final String? searchUrl;

  const OPDSFeed({
    required this.title,
    required this.id,
    required this.entries,
    this.nextUrl,
    this.searchUrl,
  });
}

/// A single entry in an OPDS feed (series, issue, or navigation node).
class OPDSEntry {
  final String title;
  final String id;
  final String? content;
  final String? thumbnailUrl;
  final String? acquisitionUrl;
  final String? navigationLink;

  const OPDSEntry({
    required this.title,
    required this.id,
    this.content,
    this.thumbnailUrl,
    this.acquisitionUrl,
    this.navigationLink,
  });

  bool get isNavigation => navigationLink != null && acquisitionUrl == null;
  bool get isAcquisition => acquisitionUrl != null;
}

/// Stateless XML parser for OPDS Atom feeds.
class OPDSParser {
  static const _atomNs = 'http://www.w3.org/2005/Atom';
  static const _opdsImageRel = 'http://opds-spec.org/image/thumbnail';
  static const _opdsImageAlt = 'http://opds-spec.org/image';
  static const _opdsAcqPrefix = 'http://opds-spec.org/acquisition';

  static OPDSFeed parseFeed(String xmlString) {
    final doc = XmlDocument.parse(xmlString);
    final feed = doc.rootElement;

    final title = _text(feed, 'title') ?? '';
    final id = _text(feed, 'id') ?? '';

    String? nextUrl;
    String? searchUrl;
    for (final link in _findLinks(feed)) {
      final rel = link.getAttribute('rel') ?? '';
      final href = link.getAttribute('href');
      if (rel == 'next' && href != null) nextUrl = href;
      if (rel == 'search' && href != null) searchUrl = href;
    }

    final entries = _findEntries(feed).map(_parseEntry).toList();

    return OPDSFeed(
      title: title,
      id: id,
      entries: entries,
      nextUrl: nextUrl,
      searchUrl: searchUrl,
    );
  }

  static OPDSEntry _parseEntry(XmlElement el) {
    final title = _text(el, 'title') ?? '';
    final id = _text(el, 'id') ?? '';
    final content = _text(el, 'content');

    String? thumbnailUrl;
    String? acquisitionUrl;
    String? navigationLink;

    for (final link in _findLinks(el)) {
      final rel = link.getAttribute('rel') ?? '';
      final href = link.getAttribute('href');
      if (href == null) continue;

      if (rel == _opdsImageRel || rel == _opdsImageAlt) {
        thumbnailUrl = href;
      } else if (rel.startsWith(_opdsAcqPrefix)) {
        acquisitionUrl = href;
      } else if (rel == 'subsection') {
        navigationLink = href;
      }
    }

    return OPDSEntry(
      title: title,
      id: id,
      content: content,
      thumbnailUrl: thumbnailUrl,
      acquisitionUrl: acquisitionUrl,
      navigationLink: navigationLink,
    );
  }

  /// Find <link> elements, trying the Atom namespace first then no namespace.
  static Iterable<XmlElement> _findLinks(XmlElement parent) {
    final withNs = parent.findElements('link', namespace: _atomNs);
    if (withNs.isNotEmpty) return withNs;
    return parent.findElements('link');
  }

  /// Find `<entry>` elements, trying the Atom namespace first then no namespace.
  static Iterable<XmlElement> _findEntries(XmlElement parent) {
    final withNs = parent.findElements('entry', namespace: _atomNs);
    if (withNs.isNotEmpty) return withNs;
    return parent.findElements('entry');
  }

  static String? _text(XmlElement parent, String name) {
    var el = parent.findElements(name, namespace: _atomNs).firstOrNull;
    el ??= parent.findElements(name).firstOrNull;
    return el?.innerText;
  }
}

/// HTTP client for fetching and navigating OPDS catalogs.
class OPDSClient {
  final ServerSource source;
  final http.Client _httpClient;

  static const int maxResponseBytes = 10 * 1024 * 1024; // 10 MB

  OPDSClient({required this.source, http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  Map<String, String> get _headers => {
        'Accept': 'application/atom+xml,application/xml,text/xml',
        ...source.authHeaders,
      };

  /// Validates a URL is not targeting localhost, private, or link-local addresses.
  static void validateUrl(String url) {
    final uri = Uri.parse(url);
    final host = uri.host;

    if (host == 'localhost' || host == '127.0.0.1' || host == '::1') {
      throw ArgumentError('OPDS URL must not target localhost: $url');
    }

    final parts = host.split('.');
    if (parts.length == 4) {
      final octets = parts.map(int.tryParse).toList();
      if (octets.every((o) => o != null)) {
        final a = octets[0]!, b = octets[1]!;
        if (a == 10) throw ArgumentError('OPDS URL must not target private network: $url');
        if (a == 172 && b >= 16 && b <= 31) throw ArgumentError('OPDS URL must not target private network: $url');
        if (a == 192 && b == 168) throw ArgumentError('OPDS URL must not target private network: $url');
        if (a == 169 && b == 254) throw ArgumentError('OPDS URL must not target link-local network: $url');
      }
    }
  }

  /// Resolve a path against the source base URL.
  String _resolveUrl(String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) {
      validateUrl(path);
      return path;
    }
    final base = Uri.parse(source.baseUrl);
    final resolved = base.resolve(path).toString();
    validateUrl(resolved);
    return resolved;
  }

  /// Fetch and parse the root catalog.
  Future<OPDSFeed> fetchRoot() => _fetchFeed(source.baseUrl);

  /// Fetch and parse a feed at the given path (relative or absolute).
  Future<OPDSFeed> fetchFeed(String path) => _fetchFeed(_resolveUrl(path));

  /// Fetch the raw bytes of an acquisition URL (for downloading archives).
  Future<http.Response> fetchAcquisition(String path) async {
    final url = _resolveUrl(path);
    final response = await _httpClient
        .get(Uri.parse(url), headers: source.authHeaders)
        .timeout(const Duration(seconds: 120));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('OPDS acquisition failed: ${response.statusCode}');
    }
    return response;
  }

  /// Resolve a thumbnail URL to an absolute URL.
  String resolveThumbnailUrl(String path) => _resolveUrl(path);

  Future<OPDSFeed> _fetchFeed(String url) async {
    final response = await _httpClient
        .get(Uri.parse(url), headers: _headers)
        .timeout(const Duration(seconds: 30));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('OPDS fetch failed: ${response.statusCode}');
    }
    if (response.bodyBytes.length > maxResponseBytes) {
      throw Exception('OPDS response exceeds ${maxResponseBytes ~/ (1024 * 1024)}MB limit');
    }
    return OPDSParser.parseFeed(response.body);
  }
}
