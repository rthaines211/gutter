// lib/services/label_client.dart
//
// HTTP client + queue session for the iPad labeller, talking to the panel
// label server (~/projects/panel-labels/server.py) proxied at
// `<baseUrl>/labeller/<path>`. Ports the session semantics of the web
// labeller's JS (~/projects/panel-labels/index.html lines 60-175): load,
// prefetch 3 ahead, optimistic save then nextTodo.
import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show BuildContext, precacheImage;
import 'package:http/http.dart' as http;

import '../config/string_utils.dart';
import 'api_client.dart';
import 'label_editor.dart';

/// Thrown by [LabelClient.importPage] when the server has no meta entry for
/// the given book/page (the 404 `{"error": "not in the set"}` response).
class LabelImportMissing implements Exception {
  final String message;
  LabelImportMissing(this.message);

  @override
  String toString() => 'LabelImportMissing: $message';
}

/// Thrown by [fixPageId] when flagging the page on the comic backend fails
/// (as opposed to the label server import), so the reader can say which.
class LabelFlagFailed implements Exception {
  final Object cause;
  LabelFlagFailed(this.cause);

  @override
  String toString() => 'LabelFlagFailed: $cause';
}

/// Reader "Fix panels" / "Fix balloons": flags the page (for the detector's
/// retraining set) under the mode's reason, then imports it into the
/// labeller's queue so [LabelScreen] can open straight to it. Returns the
/// imported page id.
Future<String> fixPageId({
  required ApiClient api,
  required LabelClient labels,
  required String comicId,
  required int page,
  required LabelMode mode,
}) async {
  try {
    await api.flagPage(
      comicId,
      page,
      reason: mode == LabelMode.panels ? 'panel_cut' : 'balloon_cut',
      zoom: mode == LabelMode.panels ? 'panels' : 'bubbles',
    );
  } catch (e) {
    throw LabelFlagFailed(e);
  }
  return labels.importPage(comicIdToPath(comicId), page);
}

/// One page's worth of state for the labeller: the server page metadata
/// plus whatever was already saved and whatever the prefill detector guessed.
class LabelPage {
  final String id;
  final int w;
  final int h;
  final List<Box> prefill;
  final List<String> prefillKinds;
  final ({List<Box> boxes, List<String> kinds, List<int> order, String note})?
      saved;

  /// Balloons mode only: the page's panel boxes, shown faint for reference.
  final List<Box> context;

  LabelPage({
    required this.id,
    required this.w,
    required this.h,
    required this.prefill,
    required this.prefillKinds,
    required this.saved,
    required this.context,
  });
}

Box _toBox(List<dynamic> raw) =>
    raw.map((v) => (v as num).toDouble()).toList();

class LabelClient {
  final String baseUrl;
  final http.Client _http;

  final Map<String, String> authHeaders;

  LabelClient({
    required this.baseUrl,
    this.authHeaders = const {},
    http.Client? httpClient,
  })
      : _http = httpClient ?? http.Client();

  Uri _uri(String path) => Uri.parse('$baseUrl/labeller/$path');

  /// GETs [path]; null on 404, decoded JSON otherwise. Throws [ApiException]
  /// on any other non-2xx status.
  Future<dynamic> _getOrNull(String path) async {
    final res = await _http.get(_uri(path), headers: authHeaders);
    if (res.statusCode == 404) return null;
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ApiException(res.statusCode, res.body);
    }
    return jsonDecode(res.body);
  }

  Future<List<String>> queue(LabelMode m) async {
    final data = await _getOrNull(m.queuePath);
    return List<String>.from(data ?? const []);
  }

  Future<Set<String>> done(LabelMode m) async {
    final data = await _getOrNull(m.donePath);
    return Set<String>.from(data ?? const []);
  }

  Future<Map<String, String>> flagReasons(LabelMode m) async {
    final data = await _getOrNull('flags.json');
    final forMode = data == null ? null : data[m.apiName];
    if (forMode == null) return {};
    return Map<String, String>.from(forMode);
  }

  Future<LabelPage> page(LabelMode m, String id) async {
    final needsContext = m == LabelMode.balloons;
    // prefill, saved and (balloons only) the saved panel label are
    // independent reads; batch them like the JS `Promise.all`.
    final results = await Future.wait([
      _getOrNull('${m.prefillDir}/$id.json'),
      _getOrNull('${m.dir}/$id.json'),
      if (needsContext) _getOrNull('labels/$id.json'),
    ]);
    final prefillJson = results[0];
    final savedJson = results[1];
    final labJson = needsContext ? results[2] : null;

    int w;
    int h;
    var prefillBoxes = <Box>[];
    var prefillKinds = <String>[];
    if (prefillJson != null) {
      w = prefillJson['w'] as int;
      h = prefillJson['h'] as int;
      final boxes = (prefillJson['boxes'] as List).cast<Map<String, dynamic>>();
      prefillBoxes = boxes.map((x) => _toBox(x['b'] as List)).toList();
      prefillKinds =
          boxes.map((x) => (x['kind'] as String?) ?? 'balloon').toList();
    } else {
      final meta = await _getOrNull('meta/$id.json');
      w = (meta?['w'] as int?) ?? 0;
      h = (meta?['h'] as int?) ?? 0;
    }

    ({List<Box> boxes, List<String> kinds, List<int> order, String note})?
        saved;
    if (savedJson != null) {
      saved = (
        boxes:
            (savedJson['boxes'] as List).map((b) => _toBox(b as List)).toList(),
        kinds: savedJson['kinds'] != null
            ? List<String>.from(savedJson['kinds'])
            : <String>[],
        order: List<int>.from(savedJson['order'] as List),
        note: savedJson['note'] as String? ?? '',
      );
    }

    var context = <Box>[];
    if (needsContext) {
      if (labJson != null) {
        context =
            (labJson['boxes'] as List).map((b) => _toBox(b as List)).toList();
      } else {
        final pre = await _getOrNull('prefill/$id.json');
        if (pre != null) {
          final boxes = (pre['boxes'] as List).cast<Map<String, dynamic>>();
          context = boxes
              .where((x) => (x['conf'] as num) >= 0.5)
              .map((x) => _toBox(x['b'] as List))
              .toList();
        }
      }
    }

    return LabelPage(
      id: id,
      w: w,
      h: h,
      prefill: prefillBoxes,
      prefillKinds: prefillKinds,
      saved: saved,
      context: context,
    );
  }

  String imageUrl(String id) => '$baseUrl/labeller/img/$id.jpg';

  Future<List<int>> numberBoxes(
    LabelMode m,
    int w,
    int h,
    List<Box> boxes,
    List<Box> panels,
  ) async {
    final res = await _http.post(
      _uri('order'),
      headers: {'Content-Type': 'application/json', ...authHeaders},
      body: jsonEncode({
        'mode': m.apiName,
        'w': w,
        'h': h,
        'boxes': boxes,
        'panels': panels,
      }),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ApiException(res.statusCode, res.body);
    }
    return List<int>.from(jsonDecode(res.body)['order'] as List);
  }

  Future<void> save(LabelMode m, String id, Map<String, dynamic> body) async {
    final res = await _http.put(
      _uri('${m.dir}/$id.json'),
      headers: {'Content-Type': 'application/json', ...authHeaders},
      body: jsonEncode(body),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ApiException(res.statusCode, res.body);
    }
  }

  Future<String> importPage(String book, int page) async {
    final res = await _http.post(
      _uri('import'),
      headers: {'Content-Type': 'application/json', ...authHeaders},
      body: jsonEncode({'book': book, 'page': page}),
    );
    if (res.statusCode == 404) {
      throw LabelImportMissing('not in the set');
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ApiException(res.statusCode, res.body);
    }
    return jsonDecode(res.body)['id'] as String;
  }
}

/// The queue walk: current page, prefetch, optimistic save. Mirrors
/// index.html's module-level state (IDS/done/i/cur) as instance fields.
class LabelSession extends ChangeNotifier {
  final LabelClient client;
  final LabelMode mode;
  final String? singleId;

  LabelSession({required this.client, required this.mode, this.singleId});

  List<String> _ids = [];
  final Set<String> _done = {};
  Map<String, String> _flagReasons = {};
  int _index = 0;
  LabelPage? _current;
  String _status = '';
  BuildContext? _context;
  bool _disposed = false;

  /// id -> in-flight or resolved page fetch, mirroring the JS `cache` Map
  /// (`fetchPage`). Shared by navigation and prefetch so a prefetched page
  /// is never re-fetched on arrival.
  final Map<String, Future<LabelPage>> _cache = {};

  /// ids whose last save attempt failed. Sticky: cleared only when that id
  /// saves successfully again, independent of navigation or other saves.
  final Set<String> _failedIds = {};

  List<String> get ids => _ids;
  Set<String> get done => _done;
  int get index => _index;
  LabelPage? get current => _current;

  /// A sticky "SAVE FAILED" message takes over whenever any id has a
  /// failed save pending, regardless of what [_status] says about
  /// whatever page is currently on screen.
  String get status {
    if (_failedIds.isNotEmpty) {
      return 'SAVE FAILED for ${_failedIds.join(', ')}: go back and save '
          'again';
    }
    return _status;
  }

  String? get flagReason =>
      _ids.isEmpty ? null : _flagReasons[_ids[_index]];

  /// Supplies a [BuildContext] so prefetch can precache page images via
  /// [CachedNetworkImageProvider]. Without one, prefetch still warms the
  /// JSON cache but skips image precaching (keeps tests widget-free).
  void attachContext(BuildContext context) {
    _context = context;
  }

  // In-flight fetches and saves outlive the screen; once it's disposed
  // their completions must not notify (or prefetch with a dead context).
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  Future<void> load() async {
    if (singleId != null) {
      _ids = [singleId!];
    } else {
      _ids = await client.queue(mode);
    }
    final doneIds = await client.done(mode);
    _done
      ..clear()
      ..addAll(doneIds);
    _flagReasons = await client.flagReasons(mode);
    final first = singleId != null ? 0 : _firstUnlabelledIndex();
    _index = first < 0 ? 0 : first;
    await _loadCurrent();
    if (first < 0 && _ids.isNotEmpty) {
      _status = 'Every page is labelled.';
      notifyListeners();
    }
  }

  /// -1 when every page is done.
  int _firstUnlabelledIndex() {
    for (var i = 0; i < _ids.length; i++) {
      if (!_done.contains(_ids[i])) return i;
    }
    return -1;
  }

  /// id -> cached/in-flight fetch. Shared across navigation and prefetch;
  /// a failed fetch evicts itself so a later real load retries instead of
  /// replaying the same failure, and prefetch callers that never await the
  /// result still get their error consumed here instead of going unhandled.
  Future<LabelPage> _fetchPage(String id) {
    final existing = _cache[id];
    if (existing != null) return existing;
    final future = client.page(mode, id);
    _cache[id] = future;
    unawaited(future.then((_) {}, onError: (Object _) {
      if (_cache[id] == future) _cache.remove(id);
    }));
    return future;
  }

  Future<void> _loadCurrent() async {
    if (_ids.isEmpty) {
      _current = null;
      _status = 'Nothing in this queue.';
      notifyListeners();
      return;
    }
    final id = _ids[_index];
    final page = await _fetchPage(id);
    // A later navigation (or nextTodo) may have moved _index on while this
    // fetch was in flight (JS: `if(IDS[i]!==id)return`). Drop a stale
    // result instead of clobbering whatever's now current.
    if (_disposed || _index >= _ids.length || _ids[_index] != id) return;
    _current = page;
    _status = page.saved != null ? 'Saved earlier' : 'New';
    notifyListeners();
    _prefetch();
  }

  void _prefetch() {
    for (var k = 1; k <= 3; k++) {
      final j = _index + k;
      if (j >= _ids.length) break;
      final id = _ids[j];
      unawaited(_fetchPage(id).then((_) {}, onError: (Object _) {}));
      final context = _context;
      if (context != null) {
        unawaited(
          // onError: a failed prefetch is not worth a FlutterError report.
          precacheImage(
            CachedNetworkImageProvider(client.imageUrl(id)),
            context,
            onError: (_, _) {},
          ),
        );
      }
    }
  }

  /// Moves to [j]; if its fetch fails (and nothing has moved on since),
  /// puts [_index] back so it keeps matching [_current].
  Future<void> _goTo(int j) async {
    final from = _index;
    _index = j;
    try {
      await _loadCurrent();
    } catch (_) {
      if (_index == j) _index = from;
      rethrow;
    }
  }

  Future<void> next() async {
    if (singleId != null) return;
    if (_index + 1 >= _ids.length) return;
    await _goTo(_index + 1);
  }

  Future<void> prev() async {
    if (singleId != null) return;
    if (_index <= 0) return;
    await _goTo(_index - 1);
  }

  Future<void> nextTodo() async {
    if (singleId != null) return;
    if (_ids.isEmpty) return;
    for (var k = 1; k <= _ids.length; k++) {
      final j = (_index + k) % _ids.length;
      if (!_done.contains(_ids[j])) {
        await _goTo(j);
        return;
      }
    }
    _status = 'Every page is labelled.';
    notifyListeners();
  }

  /// Optimistic save: marks [id] done and moves on via [nextTodo] (batch
  /// mode) before the PUT resolves; a failure un-marks it and sets a
  /// sticky "SAVE FAILED" status naming the id so the user can go back and
  /// retry.
  ///
  /// The PUT's own success/failure handling is attached before navigating
  /// (JS does the same: fires the save, then calls `nextTodo()`), so a
  /// `nextTodo()` that itself throws (e.g. the next page 500s) can't leave
  /// the save's outcome unhandled or the id stuck "done".
  Future<void> save(LabelEditor e) async {
    if (_current == null) return;
    // The editor holds _current's boxes; _index may already point at the
    // next page while its fetch is in flight (double-tapped Save, swipe).
    final page = _current!;
    final id = page.id;
    final body = e.toSaveBody(w: page.w, h: page.h);

    _done.add(id);
    _cache[id] = Future.value(
      LabelPage(
        id: id,
        w: page.w,
        h: page.h,
        prefill: page.prefill,
        prefillKinds: page.prefillKinds,
        saved: (
          boxes: List<Box>.from(e.boxes.map((b) => List<double>.from(b))),
          kinds: mode == LabelMode.balloons
              ? List<String>.from(e.kinds)
              : <String>[],
          order: List<int>.from(e.order),
          note: e.note,
        ),
        context: page.context,
      ),
    );
    _status = 'Saving…';
    notifyListeners();

    final saveFuture = client.save(mode, id, body).then((_) {
      _failedIds.remove(id);
      _status = 'Saved $id';
    }, onError: (Object _) {
      _done.remove(id);
      _cache.remove(id);
      _failedIds.add(id);
    }).whenComplete(notifyListeners);

    if (singleId == null) {
      try {
        await nextTodo();
      } catch (_) {
        // The save's own completion handling above covers done/status;
        // a broken next page shouldn't abort save() or lose that outcome.
      }
    }
    await saveFuture;
  }
}
