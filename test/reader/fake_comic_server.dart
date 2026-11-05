import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

class PageSpec {
  final int width;
  final int height;

  /// Drawn page, when a test needs one; else a flat colour.
  final img.Image? image;
  const PageSpec(this.width, this.height, [this.image]);
}

const portraitPage = PageSpec(1000, 1500);
const landscapeSpread = PageSpec(2400, 1500);

class RecordedRequest {
  final String method;
  final String path;
  final Map<String, dynamic>? jsonBody;
  RecordedRequest(this.method, this.path, this.jsonBody);

  @override
  String toString() => '$method $path';
}

/// Minimal in-test stand-in for the Go backend. Serves the endpoints the
/// reader touches on open: /settings, /comics/{id}/info,
/// /comics/{id}/pages/{n} (0-based), PUT /reading/{id}, PUT /settings,
/// GET /comics/{id}/pages/{n}/bubbles and PUT .../bubbles/order.
class FakeComicServer {
  HttpServer? _server;
  final List<RecordedRequest> requests = [];
  final Map<String, List<PageSpec>> comics = {};
  Map<String, dynamic> settings = {};
  /// comicId -> page -> sidecar JSON for GET /comics/{id}/pages/{n}/bubbles.
  final Map<String, Map<int, Map<String, dynamic>>> bubbles = {};

  /// Real-time delay before a sidecar response (late-sidecar tests).
  Duration bubblesDelay = Duration.zero;
  bool failProgressWrites = false;
  Duration settingsDelay = Duration.zero;
  final _pngCache = <String, Uint8List>{};

  String get url => 'http://127.0.0.1:${_server!.port}';

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen(_handle);
  }

  Future<void> stop() async => _server?.close(force: true);

  List<RecordedRequest> requestsWhere(bool Function(RecordedRequest) test) =>
      requests.where(test).toList();

  Uint8List _png(PageSpec spec) => spec.image != null
      ? Uint8List.fromList(img.encodePng(spec.image!, level: 1))
      : _pngCache.putIfAbsent('${spec.width}x${spec.height}', () {
        final im = img.Image(width: spec.width, height: spec.height);
        img.fill(im, color: img.ColorRgb8(120, 40, 40));
        return Uint8List.fromList(img.encodePng(im, level: 1));
      });

  // ponytail: publishState() from RemoteSession is fire-and-forget and now
  // fires on every reader rebuild across the whole suite (not just
  // remote_control_test.dart), so an in-flight POST /remote/state can still
  // be reading its body when tearDown force-closes the server. Swallow that
  // one socket-closed race the same way RemoteSession's own client side does
  // (catch (_) {}) — but ONLY for /remote/state. Every other endpoint
  // (notably /comics/{id}/pages/{n}, which the prefetcher also cancels
  // routinely and can raise the identical HttpException) must stay loud:
  // a broad catch here would hide a real handler bug as a silent
  // no-response, and ApiClient would swallow it again on the app side —
  // two layers of silence over an actual defect.
  Future<void> _handle(HttpRequest req) async {
    if (req.uri.path == '/remote/state') {
      try {
        await _handleInner(req);
      } on HttpException {
        // connection closed mid-request during forced server shutdown
      } on SocketException {
        // ditto
      }
      return;
    }
    await _handleInner(req);
  }

  Future<void> _handleInner(HttpRequest req) async {
    final path = req.uri.path;
    Map<String, dynamic>? body;
    if (req.method == 'PUT' || req.method == 'POST') {
      final raw = await utf8.decoder.bind(req).join();
      if (raw.isNotEmpty) body = jsonDecode(raw) as Map<String, dynamic>;
    }
    requests.add(RecordedRequest(req.method, path, body));

    final bubbleMatch =
        RegExp(r'^/comics/([^/]+)/pages/(\d+)/bubbles(/order)?$').firstMatch(path);
    if (bubbleMatch != null) {
      if (bubbleMatch.group(3) != null) {
        req.response.statusCode = 204; // PUT order; recorded in `requests`
        await req.response.close();
        return;
      }
      if (bubblesDelay > Duration.zero) await Future<void>.delayed(bubblesDelay);
      final sc = bubbles[Uri.decodeComponent(bubbleMatch.group(1)!)]?[int.parse(bubbleMatch.group(2)!)];
      if (sc == null) return _notFound(req);
      return _json(req, sc);
    }
    // Covers (the series page) serve page 0.
    final pageMatch =
        RegExp(r'^/comics/([^/]+)/(?:pages/(\d+)|cover)$').firstMatch(path);
    final infoMatch = RegExp(r'^/comics/([^/]+)/info$').firstMatch(path);

    if (path == '/settings') {
      if (req.method == 'GET' && settingsDelay > Duration.zero) {
        await Future<void>.delayed(settingsDelay);
      }
      _json(req, req.method == 'GET' ? settings : <String, dynamic>{});
    } else if (infoMatch != null) {
      final pages =
          comics[Uri.decodeComponent(infoMatch.group(1)!)] ?? const [];
      _json(req, {
        'title': 'Test Comic',
        'page_count': pages.length,
        'chapters': <dynamic>[],
      });
    } else if (pageMatch != null) {
      final pages = comics[Uri.decodeComponent(pageMatch.group(1)!)];
      final n = int.parse(pageMatch.group(2) ?? '0');
      if (pages == null || n >= pages.length) return _notFound(req);
      req.response.headers.contentType = ContentType('image', 'png');
      req.response.add(_png(pages[n]));
      await req.response.close();
    } else if (RegExp(r'^/reading/[^/]+$').hasMatch(path) &&
        req.method == 'PUT') {
      if (failProgressWrites) {
        req.response.statusCode = 500;
        await req.response.close();
      } else {
        _json(req, <String, dynamic>{});
      }
    } else if (RegExp(r'^/comics/[^/]+/pages/\d+/flag$').hasMatch(path) &&
        req.method == 'PUT') {
      req.response.statusCode = 204; // recorded in `requests`
      await req.response.close();
    } else if (path == '/remote/state' && req.method == 'POST') {
      req.response.statusCode = 204;
      await req.response.close();
    } else {
      return _notFound(req);
    }
  }

  Future<void> _json(HttpRequest req, Map<String, dynamic> data) async {
    req.response.headers.contentType = ContentType.json;
    req.response.write(jsonEncode(data));
    await req.response.close();
  }

  Future<void> _notFound(HttpRequest req) async {
    req.response.statusCode = 404;
    await req.response.close();
  }
}
