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

  Future<List<LocalSession>> all() async {
    final f = File(path);
    if (!await f.exists()) return [];
    try {
      return (jsonDecode(await f.readAsString()) as List<dynamic>)
          .map((e) => LocalSession.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> append(LocalSession session) async {
    final sessions = [...await all(), session];
    final f = File(path);
    await f.parent.create(recursive: true);
    final tmp = File('$path.tmp');
    await tmp.writeAsString(jsonEncode([for (final s in sessions) s.toJson()]));
    await tmp.rename(path);
  }
}
