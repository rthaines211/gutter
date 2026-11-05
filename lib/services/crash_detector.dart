import 'dart:convert';
import 'dart:io';

import 'app_logger.dart';

class CrashDetector {
  static Future<void> runOnce({
    required File heartbeatFile,
    AppLogger? logger,
  }) async {
    final log = logger ?? AppLogger.instance;
    if (!heartbeatFile.existsSync()) return;

    try {
      final raw = await heartbeatFile.readAsString();
      final map = jsonDecode(raw) as Map<String, Object?>;
      final state = (map['state'] as String?) ?? 'unknown';
      final (level, message) = switch (state) {
        'resumed' => (
            LogLevel.error,
            'previous session ended unexpectedly while in foreground'
          ),
        'paused' || 'hidden' => (
            LogLevel.info,
            'previous session ended cleanly in background'
          ),
        _ => (
            LogLevel.warn,
            'previous session ended in state: $state'
          ),
      };
      log.lifecycle(level: level, message: message, context: map);
    } catch (e) {
      log.lifecycle(
        level: LogLevel.warn,
        message: 'previous heartbeat unreadable: $e',
      );
    } finally {
      try {
        await heartbeatFile.delete();
      } catch (_) {}
    }
  }
}
