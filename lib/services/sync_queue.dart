import 'dart:convert';
import 'dart:io';

import 'app_logger.dart';

class SyncQueue {
  final String queuePath;

  SyncQueue({required this.queuePath});

  /// Tail of the pending read-modify-writes per file. Keyed by path, not
  /// instance: provider rebuilds hand out several instances for one file, and
  /// unserialized, a page-turn enqueue racing the drainer's removeFirst (or
  /// another enqueue) overwrote the other's write and lost an entry.
  static final Map<String, Future<void>> _locks = {};

  Future<void> _locked(Future<void> Function() body) {
    final next = (_locks[queuePath] ?? Future.value())
        .catchError((_) {})
        .then((_) => body());
    _locks[queuePath] = next;
    return next;
  }

  Future<void> enqueue(Map<String, dynamic> entry) => _locked(() async {
        final entries = await readAll();
        entries.add({
          ...entry,
          'queued_at': DateTime.now().toIso8601String(),
        });
        await _write(entries);
      });

  /// Unparseable content is treated as an empty queue rather than thrown.
  /// Every caller propagates a throw from here, and [SyncEngine] drains the
  /// outbox *before* the `/sync` pull — so one corrupt byte stopped all
  /// syncing permanently and silently (the call sites swallow errors), leaving
  /// the mirror frozen with no request ever reaching the server. The content
  /// is already lost either way; the next enqueue rewrites the file.
  Future<List<Map<String, dynamic>>> readAll() async {
    final file = File(queuePath);
    if (!file.existsSync()) return [];
    final content = await file.readAsString();
    if (content.trim().isEmpty) return [];
    try {
      final list = jsonDecode(content) as List<dynamic>;
      // whereType, not cast: cast is lazy and defers the TypeError to the
      // caller's first iteration, which is outside the drainer's try block.
      return list.whereType<Map<String, dynamic>>().toList();
    } catch (e) {
      AppLogger.instanceOrNull?.sync(
        level: LogLevel.warn,
        message: 'outbox unreadable, discarding',
        context: {'path': queuePath, 'error': e.toString()},
      );
      return [];
    }
  }

  Future<void> removeFirst() => _locked(() async {
        final entries = await readAll();
        if (entries.isEmpty) return;
        entries.removeAt(0);
        await _write(entries);
      });

  Future<void> clear() => _locked(() async {
        final file = File(queuePath);
        if (file.existsSync()) await file.delete();
      });

  Future<int> get pendingCount async => (await readAll()).length;

  Future<void> _write(List<Map<String, dynamic>> entries) async {
    final file = File(queuePath);
    await file.parent.create(recursive: true);
    // Temp + rename is atomic: a kill mid-write used to leave a truncated
    // file, which readAll discards — losing every queued write at once.
    final tmp = File('$queuePath.tmp');
    await tmp.writeAsString(jsonEncode(entries), flush: true);
    await tmp.rename(queuePath);
  }
}
