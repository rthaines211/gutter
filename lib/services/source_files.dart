import 'dart:io';

import 'package:path/path.dart' as p;

/// Deletes a source's on-device data under [docsDir]: its mirror database
/// (drift's `mirror_<id>.sqlite` and WAL files), synced covers, and cache
/// dir (outbox, local sessions, cached API responses). Missing paths are
/// fine. Downloads are the download manager's ([DownloadManager.deleteSource]).
Future<void> deleteSourceFiles(String docsDir, String sourceId) async {
  final db = p.join(docsDir, 'mirror_$sourceId.sqlite');
  for (final f in [db, '$db-wal', '$db-shm']) {
    final file = File(f);
    if (await file.exists()) await file.delete();
  }
  for (final d in ['covers', 'cache']) {
    final dir = Directory(p.join(docsDir, d, sourceId));
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}
