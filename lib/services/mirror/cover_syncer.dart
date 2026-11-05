import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'mirror_database.dart';

/// Downloads cover thumbnails for mirrored series into permanent storage
/// (`<coversDir>/<seriesId>.jpg`). Sequential and best-effort: failures are
/// skipped and retried on the next run because coverSyncedAt is only set
/// after a successful write.
class CoverSyncer {
  final MirrorDatabase db;
  final String baseUrl;
  final String coversDir;
  final http.Client httpClient;

  CoverSyncer({
    required this.db,
    required this.baseUrl,
    required this.coversDir,
    http.Client? httpClient,
  }) : httpClient = httpClient ?? http.Client();

  /// Sweep in progress per covers dir. Every drain (incl. the 60s periodic
  /// one) kicks a sweep unawaited; on a first sync of hundreds of series they
  /// piled up, re-downloading the same covers onto the same files at once.
  static final Map<String, Future<void>> _running = {};

  Future<void> syncCovers() => _running[coversDir] ??=
      _sweep().catchError((_) {}).whenComplete(() {
        // Block body: an arrow would return the removed future — this one —
        // and whenComplete would await itself forever.
        _running.remove(coversDir);
      });

  Future<void> _sweep() async {
    final rows = await db.listSeriesNeedingCovers();
    for (final row in rows) {
      try {
        final payload = jsonDecode(row.payload) as Map<String, dynamic>;
        final coverUrl = payload['cover_url'] as String? ?? '';
        if (coverUrl.isEmpty) {
          // No cover server-side; mark synced so we don't retry forever.
          await db.markCoverSynced(row.id, row.updatedAt);
          continue;
        }
        final resp = await httpClient
            .get(Uri.parse('$baseUrl$coverUrl'))
            .timeout(const Duration(seconds: 30));
        if (resp.statusCode != 200) continue;
        final path = p.join(coversDir, '${row.id}.jpg');
        await Directory(coversDir).create(recursive: true);
        // Temp + rename so a tile never renders a half-written cover.
        final tmp = File('$path.tmp');
        await tmp.writeAsBytes(resp.bodyBytes, flush: true);
        await tmp.rename(path);
        await db.markCoverSynced(row.id, row.updatedAt);
      } catch (_) {
        // Network error or malformed payload — skip row, retry on next sync trigger.
      }
    }
  }
}
