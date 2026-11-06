import 'dart:convert';
import 'dart:io';

/// One reading session kept on the device (Komga has no session API).
class LocalSession {
  final String comicId;
  final String seriesId;
  final DateTime startedAt;
  final int pagesRead;
  final int durationS;

  const LocalSession({
    required this.comicId,
    required this.seriesId,
    required this.startedAt,
    required this.pagesRead,
    required this.durationS,
  });

  factory LocalSession.fromJson(Map<String, dynamic> j) => LocalSession(
        comicId: j['comic_id'] as String,
        seriesId: j['series_id'] as String,
        startedAt: DateTime.parse(j['started_at'] as String),
        pagesRead: j['pages_read'] as int,
        durationS: j['duration_s'] as int,
      );

  Map<String, dynamic> toJson() => {
        'comic_id': comicId,
        'series_id': seriesId,
        'started_at': startedAt.toIso8601String(),
        'pages_read': pagesRead,
        'duration_s': durationS,
      };
}

/// A source's sessions as one JSON list (`cache/<sourceId>/sessions.json`).
// ponytail: rewrites the whole file per session; fine for years of reading
// (~100 bytes each). Move to the mirror if it ever gets big.
class LocalSessionStore {
  final String path;
  LocalSessionStore(this.path);

  /// Appends per file run one at a time (a reader session can end while the
  /// outbox replays a queued one).
  static final Map<String, Future<void>> _chains = {};

  Future<List<LocalSession>> all() async {
    try {
      return await _read();
    } catch (_) {
      return [];
    }
  }

  /// Throws [FormatException] for an unreadable file rather than replacing
  /// years of history with one session.
  Future<List<LocalSession>> _read() async {
    final f = File(path);
    if (!await f.exists()) return [];
    final raw = await f.readAsString();
    try {
      return (jsonDecode(raw) as List<dynamic>)
          .map((e) => LocalSession.fromJson(e as Map<String, dynamic>))
          .toList();
    } on FormatException {
      rethrow;
    } catch (e) {
      throw FormatException('sessions.json: $e');
    }
  }

  Future<void> append(LocalSession session) {
    final next = (_chains[path] ?? Future.value())
        .catchError((_) {})
        .then((_) => _append(session));
    _chains[path] = next;
    return next;
  }

  Future<void> _append(LocalSession session) async {
    final sessions = [...await _read(), session];
    await File(path).parent.create(recursive: true);
    final tmp = File('$path.${DateTime.now().microsecondsSinceEpoch}.tmp');
    await tmp.writeAsString(jsonEncode([for (final s in sessions) s.toJson()]));
    await tmp.rename(path);
  }
}
