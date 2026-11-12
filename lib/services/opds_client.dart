import 'dart:convert';
import 'dart:math';

import 'package:xml/xml.dart';

import '../models/bookmark.dart';
import '../models/chapter.dart';
import '../models/comic_info.dart';
import '../models/creator.dart';
import '../models/series.dart';
import '../models/sync_response.dart';
import 'api_client.dart';
import 'app_logger.dart';
import 'komga_client.dart' show LocalReaderData;
import 'local_session_store.dart';

const _atomNs = 'http://www.w3.org/2005/Atom';
const _pseNs = 'http://vaemendis.net/opds-pse/ns';
const _pseStream = 'http://vaemendis.net/opds-pse/stream';

/// One `<link>` of an OPDS feed or entry. [count] is OPDS-PSE's `pse:count`
/// (any prefix: Kavita writes `p5:count`).
class OpdsLink {
  final String rel;
  final String href;
  final String type;
  final int? count;
  const OpdsLink(this.rel, this.href, this.type, this.count);
}

class OpdsEntry {
  final String id;
  final String title;

  /// `<updated>` as written.
  final String? updated;
  final List<OpdsLink> links;
  const OpdsEntry(this.id, this.title, this.updated, this.links);

  String? _href(String rel) =>
      links.where((l) => l.rel == rel).firstOrNull?.href;

  /// The OPDS-PSE page-streaming link (`{pageNumber}` template, 0-based).
  OpdsLink? get stream => links.where((l) => l.rel == _pseStream).firstOrNull;
  String? get thumbnail => _href('http://opds-spec.org/image/thumbnail');
  String? get image => _href('http://opds-spec.org/image');
  bool get downloadable =>
      links.any((l) => l.rel.startsWith('http://opds-spec.org/acquisition'));

  /// The catalog feed this entry opens, for navigation entries.
  String? get navigation => links
      .where((l) =>
          l.rel == 'subsection' ||
          (l.rel.isEmpty && l.type.contains('opds-catalog')))
      .firstOrNull
      ?.href;
}

class OpdsFeed {
  final String title;
  final String? updated;
  final List<OpdsEntry> entries;
  final List<OpdsLink> links;
  const OpdsFeed(this.title, this.updated, this.entries, this.links);

  String? get next => links.where((l) => l.rel == 'next').firstOrNull?.href;
  String? get image =>
      links.where((l) => l.rel == 'http://opds-spec.org/image').firstOrNull?.href;
}

/// Kavita puts a read-state glyph before every title (⭘ unread, ◔◑◕ partly
/// read, ⬤ read).
final _readGlyph = RegExp('^[⭘◔◑◕⬤●○◯]\\s*');

Iterable<XmlElement> _atom(XmlElement parent, String name) =>
    parent.childElements.where((e) =>
        e.name.local == name &&
        (e.name.namespaceUri == _atomNs || e.name.namespaceUri == null));

String? _text(XmlElement parent, String name) =>
    _atom(parent, name).firstOrNull?.innerText.trim();

List<OpdsLink> _links(XmlElement parent) => [
      for (final l in _atom(parent, 'link'))
        if (l.getAttribute('href') case final href?)
          OpdsLink(
            l.getAttribute('rel') ?? '',
            href,
            l.getAttribute('type') ?? '',
            int.tryParse(l.getAttribute('count', namespace: _pseNs) ?? ''),
          ),
    ];

/// An OPDS 1.x (Atom) feed. Throws [FormatException] for anything else, such
/// as the HTML login page a wrong address gets.
OpdsFeed parseOpdsFeed(String xml) {
  final XmlElement feed;
  try {
    feed = XmlDocument.parse(xml).rootElement;
  } on XmlException catch (e) {
    throw FormatException('Not an OPDS feed: $e');
  }
  if (feed.name.local != 'feed') {
    throw const FormatException('Not an OPDS feed');
  }
  return OpdsFeed(
    _text(feed, 'title') ?? '',
    _text(feed, 'updated'),
    [
      for (final e in _atom(feed, 'entry'))
        OpdsEntry(
          _text(e, 'id') ?? '',
          (_text(e, 'title') ?? '').replaceFirst(_readGlyph, ''),
          _text(e, 'updated'),
          _links(e),
        ),
    ],
    _links(feed),
  );
}

// An OPDS comic has no server-side id the app can turn into URLs, so its id
// carries what the reader needs: base64url of "<page count>|<PSE template>".
// The template is relative to the catalog when it sits under it, which keeps
// Kavita's API key (in its catalog path) out of ids and file names.
// ponytail: a file whose page count changes gets a new id (and loses its
// local progress); fine while servers rarely rewrite files.

String _noQuery(String url) => url.split('?').first;

String _b64(String s) => base64Url.encode(utf8.encode(s)).replaceAll('=', '');
String _unb64(String s) => utf8.decode(base64Url.decode(base64Url.normalize(s)));

String _rel(String path, String catalogPath) =>
    catalogPath.isNotEmpty && path.startsWith('$catalogPath/')
        ? path.substring(catalogPath.length + 1)
        : path;

String _abs(String rel, String catalogPath) =>
    rel.startsWith('/') ? rel : '$catalogPath/$rel';

/// The app's id for a comic with [count] pages streamed from [streamPath] (a
/// path on the source's origin, with its `{pageNumber}` placeholder).
String opdsComicId(int count, String streamPath, String catalogPath) =>
    _b64('$count|${_rel(streamPath, catalogPath)}');

({int count, String path})? _comic(String id, String catalogPath) {
  try {
    final s = _unb64(id);
    final bar = s.indexOf('|');
    return (
      count: int.parse(s.substring(0, bar)),
      path: _abs(s.substring(bar + 1), catalogPath),
    );
  } catch (_) {
    return null;
  }
}

/// Page [page] (0-based, as OPDS-PSE counts) of comic [comicId]; empty for an
/// id that isn't an OPDS one.
String opdsPageUrl(String baseUrl, String catalogPath, String comicId, int page) {
  final c = _comic(comicId, catalogPath);
  if (c == null) return '';
  return '$baseUrl${c.path}'
      .replaceAll('{pageNumber}', '$page')
      .replaceAll('{maxWidth}', '2048');
}

/// Where [DownloadManager] fetches an OPDS comic: the page template, then
/// `#` and the page count.
String opdsDownloadUrl(String baseUrl, String catalogPath, String comicId) {
  final c = _comic(comicId, catalogPath);
  return c == null ? '' : '$baseUrl${c.path}#${c.count}';
}

/// A series id: the series feed's path, relative to the catalog.
String opdsFeedId(String path, String catalogPath) =>
    _b64(_rel(path, catalogPath));

class _Visit {
  final String path;
  final bool root;
  final String? name;
  final String? image;

  /// Set for a feed's next page: its books join that series.
  final _Series? series;
  const _Visit(this.path, {this.root = false, this.name, this.image, this.series});
}

class _Series {
  final String path;
  String name;
  String? image;
  DateTime? stamp;
  final issues = <Map<String, dynamic>>[];
  _Series(this.path, this.name, this.image);
}

/// A generic OPDS 1.x catalog with OPDS-PSE page streaming, behind the
/// [ApiClient] surface the mirror and reader use, like [KomgaClient].
/// [baseUrl] is the source's origin and [catalogPath] the catalog on it.
/// Every request goes to [baseUrl]: a link to another host is dropped, so
/// the login never leaves the origin. Reading progress stays on the device.
class OpdsClient extends ApiClient with LocalReaderData {
  OpdsClient({
    required super.baseUrl,
    required this.catalogPath,
    required super.deviceId,
    super.httpClient,
    super.onRequestOutcome,
    super.authHeaders,
    this.sessions,
    this.maxFeeds = 2000,
  });

  final String catalogPath;

  /// Feeds one sync may read.
  /// ponytail: about 2000 series; raise it, or crawl incrementally, for
  /// libraries bigger than that.
  final int maxFeeds;

  @override
  final LocalSessionStore? sessions;

  late final Uri _origin = Uri.parse(baseUrl);

  /// Root entries that list books already reached another way (or never
  /// end): on-deck, latest, collections, reading lists, publishers, search,
  /// and flat lists of every book (Stump "All books", Codex "Latest
  /// Unread"), which would take the books from their series.
  static final _views = RegExp(
      'deck|keep|latest|recent|want|reading-?list|readlist|collection|all-?books|'
      'publisher|search|favou?rite|history|unread',
      caseSensitive: false);

  Future<OpdsFeed> _feed(String path) async =>
      parseOpdsFeed(await requestText(path));

  /// [href] from the feed at [from] as a path (and query) on this origin, or
  /// null for another host. Same host with another scheme or port (a server
  /// behind a proxy often writes its internal address) is rebased onto
  /// [baseUrl]: only the path is kept, so nothing is ever sent elsewhere.
  String? _local(String? href, String from) {
    if (href == null || href.isEmpty) return null;
    final Uri u;
    try {
      u = _origin.resolve(from).resolve(href);
    } on FormatException {
      return null;
    }
    if (u.host.toLowerCase() != _origin.host.toLowerCase()) return null;
    // Uri escapes the template's braces.
    return '${u.path}${u.hasQuery ? '?${u.query}' : ''}'.replaceAllMapped(
        RegExp(r'%7B(\w+)%7D', caseSensitive: false), (m) => '{${m[1]}}');
  }

  /// Walks the catalog from [start]: navigation entries are followed (root
  /// views skipped), `next` pages joined to their feed, and every feed with
  /// streamable books is a series. Feeds and books are each taken once.
  Future<List<_Series>> _crawl(String start,
      {void Function(int done, int total)? onProgress}) async {
    final queue = [_Visit(start, root: true)];
    final seenFeeds = {start};
    final seenBooks = <String>{};
    final series = <String, _Series>{};
    var read = 0, unstreamable = 0;
    while (queue.isNotEmpty && read < maxFeeds) {
      final batch = queue.take(min(6, maxFeeds - read)).toList();
      queue.removeRange(0, batch.length);
      // Any failure fails the sync: a series missing from a partial crawl
      // would be pruned from the mirror with its progress.
      final feeds = await Future.wait(batch.map((v) => _feed(v.path)));
      for (var i = 0; i < batch.length; i++) {
        final v = batch[i], feed = feeds[i];
        read++;
        final s = v.series ??
            _Series(v.path, v.name ?? feed.title,
                v.image ?? _local(feed.image, v.path));
        for (final e in feed.entries) {
          final stream = e.stream;
          final nav = e.navigation;
          if (stream == null && nav != null) {
            // Without queries: every Codex link carries `topCollection=`.
            if (v.root &&
                _views.hasMatch(
                    '${e.title} ${_noQuery(e.id)} ${_noQuery(nav)}')) {
              continue;
            }
            final path = _local(nav, v.path);
            if (path == null) continue;
            // The same feed with another query is a re-sort or filter of it
            // (Codex "Order By ..."), never a new shelf. Pages come as the
            // feed's own `next` link.
            if (_noQuery(path) == _noQuery(v.path)) continue;
            if (!seenFeeds.add(path)) continue;
            queue.add(_Visit(path,
                name: e.title,
                image: _local(e.image ?? e.thumbnail, v.path)));
            continue;
          }
          final count = stream?.count ?? 0;
          if (stream == null || count <= 0) {
            if (e.downloadable) unstreamable++;
            continue;
          }
          // Kavita repeats the book in progress at the top of its series.
          if (e.title.startsWith('Continue Reading from')) continue;
          final template = _local(stream.href, v.path);
          if (template == null) continue;
          final id = opdsComicId(count, template, catalogPath);
          if (!seenBooks.add(id)) continue;
          final thumb = _local(e.thumbnail ?? e.image, v.path);
          s.image ??= _local(e.image, v.path) ?? thumb;
          s.issues.add({
            'id': id,
            'name': e.title,
            'number': RegExp(r'#\s*(\d[\w.]*)').firstMatch(e.title)?[1],
            'cover_url': thumb ?? '',
            'total_pages': count,
          });
          // Kavita stamps every entry with the request time, which would
          // refetch every cover on every sync: only a stamp that differs
          // from the feed's own counts.
          final at = e.updated == feed.updated ? null : DateTime.tryParse(e.updated ?? '');
          if (at != null && (s.stamp == null || at.isAfter(s.stamp!))) s.stamp = at;
          series.putIfAbsent(s.path, () => s);
        }
        final next = _local(feed.next, v.path);
        if (next != null && seenFeeds.add(next)) {
          queue.add(_Visit(next, series: s));
        }
      }
      onProgress?.call(read, read + queue.length);
    }
    if (queue.isNotEmpty || unstreamable > 0) {
      AppLogger.instanceOrNull?.sync(
        level: LogLevel.warn,
        message: 'OPDS crawl incomplete',
        context: {
          // Books with only a download link: Gutter reads OPDS through page
          // streaming (OPDS-PSE), so these are left out.
          'withoutPageStreaming': unstreamable,
          if (queue.isNotEmpty) 'feedsNotRead': queue.length,
        },
      );
    }
    return series.values.toList();
  }

  Map<String, dynamic> _toSync(_Series s) {
    final stamp = s.stamp?.toUtc().toIso8601String();
    return {
      'id': opdsFeedId(s.path, catalogPath),
      'name': s.name,
      'updated_at': stamp,
      'created_at': stamp,
      'folder_path': '',
      'issue_count': s.issues.length,
      'cover_url': s.image ?? '',
      'genres': const [],
      'issues': s.issues,
    };
  }

  /// A full crawl every sync (OPDS has no changes feed). `progress` is empty
  /// and `progress_ids` lists every comic, so the mirror keeps the progress
  /// it has and prunes it only for comics that are gone.
  @override
  Future<SyncResponse> fetchSync(
      {required int since, void Function(int done, int total)? onSeries}) async {
    final series = (await _crawl(catalogPath, onProgress: onSeries))
        .map(_toSync)
        .toList();
    return SyncResponse(
      serverTime: DateTime.now().millisecondsSinceEpoch,
      series: series,
      progress: const [],
      seriesIds: [for (final s in series) s['id'] as String],
      progressIds: [
        for (final s in series)
          for (final i in s['issues'] as List) (i as Map)['id'] as String,
      ],
      serverHasQueues: false,
    );
  }

  @override
  Future<Map<String, dynamic>> fetchSeriesRaw(String seriesId) async {
    final String path;
    try {
      path = _abs(_unb64(seriesId), catalogPath);
    } catch (_) {
      throw ApiException(404, 'No such series');
    }
    final found = (await _crawl(path)).where((s) => s.path == path);
    if (found.isEmpty) throw ApiException(404, 'No such series');
    return _toSync(found.first);
  }

  @override
  Future<SeriesDetail> fetchSeriesDetail(String seriesId) async =>
      SeriesDetail.fromJson(await fetchSeriesRaw(seriesId));

  /// The page count is in the id; the name comes from the mirror.
  @override
  Future<ComicInfo> getComicInfo(String comicId) async {
    final c = _comic(comicId, catalogPath);
    if (c == null) throw ApiException(404, 'No such comic');
    return ComicInfo(title: '', pageCount: c.count);
  }

  @override
  String pageUrl(String comicId, int pageNum) =>
      opdsPageUrl(baseUrl, catalogPath, comicId, pageNum);

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

  /// 200 when the catalog answers with an OPDS feed; null for anything else
  /// that isn't an HTTP error (a web page at the wrong address).
  @override
  Future<int?> probeStatus() async {
    try {
      parseOpdsFeed(await requestText(catalogPath,
          timeout: const Duration(seconds: 10)));
      return 200;
    } on ApiException catch (e) {
      return e.statusCode;
    } catch (_) {
      return null;
    }
  }
}
