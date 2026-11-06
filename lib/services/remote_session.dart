import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Incremental SSE frame parser. Frames are separated by a blank line; only
/// `data:` lines carry payloads and `:` lines are keepalive comments.
/// Buffers across chunk boundaries — a frame is routinely split by TCP.
class SseParser {
  final StringBuffer _buffer = StringBuffer();

  List<String> add(String chunk) {
    _buffer.write(chunk);
    var text = _buffer.toString();
    final out = <String>[];
    while (true) {
      final idx = text.indexOf('\n\n');
      if (idx < 0) break;
      final frame = text.substring(0, idx);
      text = text.substring(idx + 2);
      for (final line in const LineSplitter().convert(frame)) {
        if (line.startsWith('data: ')) out.add(line.substring(6));
      }
    }
    _buffer
      ..clear()
      ..write(text);
    return out;
  }
}

/// The iPad reader's state as the phone sees it.
class RemoteSnapshot {
  final String comicId;
  final String series;
  final int page;
  final int totalPages;
  final bool bookmarked;
  final bool hasNextIssue;

  /// 'page' or 'scroll'. Remote page turns are page-mode only in v1 —
  /// ScrollReader cannot be driven externally.
  final String readingMode;

  const RemoteSnapshot({
    required this.comicId,
    required this.series,
    required this.page,
    required this.totalPages,
    required this.bookmarked,
    required this.hasNextIssue,
    required this.readingMode,
  });

  factory RemoteSnapshot.fromJson(Map<String, dynamic> j) => RemoteSnapshot(
        comicId: j['comicId'] as String? ?? '',
        series: j['series'] as String? ?? '',
        // `as num?` not `as int?`: a JSON 4.0 is a double, and an unguarded
        // cast throws inside the .map() that feeds the phone's StreamProvider,
        // which kills that stream permanently — the remote silently stops
        // updating until app restart.
        page: (j['page'] as num?)?.toInt() ?? 0,
        totalPages: (j['totalPages'] as num?)?.toInt() ?? 0,
        bookmarked: j['bookmarked'] as bool? ?? false,
        hasNextIssue: j['hasNextIssue'] as bool? ?? false,
        readingMode: j['readingMode'] as String? ?? 'page',
      );

  Map<String, dynamic> toJson() => {
        'comicId': comicId,
        'series': series,
        'page': page,
        'totalPages': totalPages,
        'bookmarked': bookmarked,
        'hasNextIssue': hasNextIssue,
        'readingMode': readingMode,
      };
}

/// SSE client plus command/state POSTs for remote control. Uses
/// package:http only — Client.send() exposes the response as a byte stream,
/// which is all SSE needs. No new dependency, no WebSocket upgrade.
class RemoteSession {
  final String baseUrl;
  final Map<String, String> authHeaders;

  /// False on a source without the relay (not a Gutter server, or the store
  /// app): every call is a no-op, so nothing polls an endpoint that isn't there.
  final bool enabled;
  final http.Client _client;
  final Future<void> Function(Duration) _sleep;

  /// A stream with no bytes for this long is treated as dead and reconnected.
  /// The server pings every 15s, so this misses two before giving up. Without
  /// it a blackholed TCP connection looks healthy forever and
  /// [connectionChanges] lies about the one failure it exists to report.
  final Duration _idleTimeout;

  bool _disposed = false;

  /// The most recent snapshot body. Doubles as the dedupe key (the iPad
  /// publishes from build(), which runs far more often than state changes)
  /// and as what to re-post when a reader stream reconnects.
  String? _stateJson;

  bool _connected = false;
  final StreamController<bool> _connection = StreamController<bool>.broadcast();

  /// [sleep] replaces the backoff wait mechanism; tests inject a fake that
  /// records durations without actually waiting. Defaults to a real delay.
  RemoteSession({
    required this.baseUrl,
    this.authHeaders = const {},
    this.enabled = true,
    http.Client? httpClient,
    Future<void> Function(Duration)? sleep,
    Duration idleTimeout = const Duration(seconds: 35),
  })  : _client = httpClient ?? http.Client(),
        _sleep = sleep ?? Future.delayed,
        _idleTimeout = idleTimeout;

  /// Whether a stream on this session currently has a live connection.
  ///
  /// Seeds the current value, so a widget that subscribes late is told the
  /// truth immediately instead of waiting for the next flap.
  ///
  /// ponytail: one flag per session, not per stream. Each device opens
  /// exactly one role (the iPad 'reader', the phone 'remote'), so they can't
  /// disagree in practice. Make it per-stream if a device ever opens both.
  Stream<bool> get connectionChanges async* {
    yield _connected;
    yield* _connection.stream;
  }

  void _setConnected(bool value) {
    if (value == _connected || _connection.isClosed) return;
    _connected = value;
    _connection.add(value);
  }

  /// A never-ending stream of decoded frames for [role] ('reader' or
  /// 'remote'). Reconnects with backoff on any drop; it does not surface
  /// errors, because a remote that dies on the first Wi-Fi blip is useless.
  ///
  /// Cancelling the returned subscription stops everything: the reconnect
  /// loop ends and the in-flight HTTP connection is released, so the server
  /// stops counting this client. That matters because the backend's session
  /// identity is implicit — "the iPad that is reading" is whoever holds an
  /// open `role=reader` stream — so a stream that outlives its reader makes
  /// the relay lie about who is connected.
  ///
  /// Single-subscription, one connection per call: open one per reader
  /// session and hold it. [dispose] tears down the whole session (the shared
  /// http.Client) and ends any streams still running.
  Stream<Map<String, dynamic>> events(String role) {
    if (!enabled) return const Stream.empty();
    // Completed by onCancel; raced against every await so a cancel is honored
    // while parked on a chunk read or mid-backoff, not only at a yield point.
    final stop = Completer<void>();
    StreamSubscription<String>? inner;
    late final StreamController<Map<String, dynamic>> controller;

    Future<void> run() async {
      var backoff = const Duration(seconds: 1);
      while (!stop.isCompleted && !_disposed) {
        try {
          final req = http.Request(
            'GET',
            Uri.parse('$baseUrl/remote/events?role=$role'),
          )
            ..headers.addAll(authHeaders)
            ..headers['Accept'] = 'text/event-stream';
          final resp = await _client.send(req);
          if (resp.statusCode != 200) {
            // Drain, or the socket is held open by an unread body and the
            // connection pool hands out a poisoned connection next time.
            await resp.stream.drain<void>();
            throw http.ClientException('${resp.statusCode}');
          }
          // The hub forgets the stored snapshot the moment the last reader
          // stream drops, so a reconnect means the server no longer knows our
          // state. build() won't republish until reader state changes, which
          // could be minutes, so resend now.
          _republishState();

          final parser = SseParser();
          final closed = Completer<void>();
          Timer? watchdog;
          void finish() {
            watchdog?.cancel();
            watchdog = null;
            if (!closed.isCompleted) closed.complete();
          }

          // Reset by any bytes at all, keepalive comments included: the chunk
          // callback fires before SseParser filters `:` lines out.
          void armWatchdog() {
            watchdog?.cancel();
            watchdog = Timer(_idleTimeout, finish);
          }

          inner = resp.stream.transform(utf8.decoder).listen(
            (chunk) {
              // Reset backoff only once bytes actually arrive. Resetting on
              // the 200 alone lets a server that accepts and immediately
              // drops hot-loop at 1s forever.
              backoff = const Duration(seconds: 1);
              _setConnected(true);
              armWatchdog();
              for (final payload in parser.add(chunk)) {
                if (!controller.isClosed) {
                  controller.add(jsonDecode(payload) as Map<String, dynamic>);
                }
              }
            },
            onDone: finish,
            onError: (_) => finish(),
            cancelOnError: true,
          );
          armWatchdog();
          await Future.any([closed.future, stop.future]);
          watchdog?.cancel();
          watchdog = null;
          await inner?.cancel();
          inner = null;
        } catch (_) {
          // fall through to the backoff below
        }
        _setConnected(false);
        if (stop.isCompleted || _disposed) break;
        await Future.any([_sleep(backoff), stop.future]);
        backoff = backoff * 2;
        if (backoff > const Duration(seconds: 30)) {
          backoff = const Duration(seconds: 30);
        }
      }
      if (!controller.isClosed) controller.close();
    }

    controller = StreamController<Map<String, dynamic>>(
      onListen: run,
      onCancel: () async {
        if (!stop.isCompleted) stop.complete();
        await inner?.cancel();
        inner = null;
      },
    );
    return controller.stream;
  }

  /// Returns false when the server reports no reader connected (409).
  Future<bool> sendCommand(String type, {int? page}) async {
    if (!enabled) return false;
    try {
      final resp = await _client.post(
        Uri.parse('$baseUrl/remote/command'),
        headers: {'Content-Type': 'application/json', ...authHeaders},
        body: jsonEncode({'type': type, 'page': page ?? 0}),
      );
      return resp.statusCode == 204;
    } catch (_) {
      return false;
    }
  }

  /// Fire-and-forget, and a no-op when the snapshot is unchanged — the iPad
  /// calls this from build(). Deduping lives here rather than in the reader
  /// because this object is the only one that also knows when its connection
  /// reset and the server therefore forgot.
  Future<void> publishState(RemoteSnapshot snapshot) async {
    if (!enabled) return;
    final body = jsonEncode(snapshot.toJson());
    if (body == _stateJson) return;
    _stateJson = body;
    await _postState(body);
  }

  void _republishState() {
    final body = _stateJson;
    if (body != null) _postState(body);
  }

  Future<void> _postState(String body) async {
    try {
      await _client.post(
        Uri.parse('$baseUrl/remote/state'),
        headers: {'Content-Type': 'application/json', ...authHeaders},
        body: body,
      );
    } catch (_) {}
  }

  void dispose() {
    _disposed = true;
    _setConnected(false);
    _connection.close();
    _client.close();
  }
}
