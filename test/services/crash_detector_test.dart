import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/services/app_logger.dart';
import 'package:comic_reader_app/services/crash_detector.dart';

Directory _tempDir() => Directory.systemTemp.createTempSync('cd_test_');

void main() {
  setUp(() => AppLogger.resetForTest());

  test('absent file -> no log event, no error', () async {
    final dir = _tempDir();
    final logger = AppLogger.forTest();

    await CrashDetector.runOnce(
      heartbeatFile: File('${dir.path}/heartbeat.json'),
      logger: logger,
    );

    expect(logger.snapshot(), isEmpty);
    dir.deleteSync(recursive: true);
  });

  test('unparseable file -> warn log + file deleted', () async {
    final dir = _tempDir();
    final file = File('${dir.path}/heartbeat.json');
    await file.writeAsString('not-json');
    final logger = AppLogger.forTest();

    await CrashDetector.runOnce(heartbeatFile: file, logger: logger);

    final entries = logger.snapshot(category: LogCategory.lifecycle);
    expect(entries.single.level, LogLevel.warn);
    expect(entries.single.message, contains('unreadable'));
    expect(file.existsSync(), isFalse);
    dir.deleteSync(recursive: true);
  });

  test('state=resumed -> error log with full context', () async {
    final dir = _tempDir();
    final file = File('${dir.path}/heartbeat.json');
    final payload = {
      'ts': '2026-05-26T10:00:00.000Z',
      'state': 'resumed',
      'route': '/reader',
      'comicId': 'abc',
      'page': 42,
      'totalPages': 100,
      'imageCache': {'count': 80, 'bytes': 240000000},
    };
    await file.writeAsString(jsonEncode(payload));
    final logger = AppLogger.forTest();

    await CrashDetector.runOnce(heartbeatFile: file, logger: logger);

    final entries = logger.snapshot(category: LogCategory.lifecycle);
    expect(entries.single.level, LogLevel.error);
    expect(entries.single.message, contains('unexpectedly'));
    expect(entries.single.context['route'], '/reader');
    expect(entries.single.context['comicId'], 'abc');
    expect(file.existsSync(), isFalse);
    dir.deleteSync(recursive: true);
  });

  test('state=paused -> info log', () async {
    final dir = _tempDir();
    final file = File('${dir.path}/heartbeat.json');
    await file.writeAsString(jsonEncode({'state': 'paused', 'route': '/library'}));
    final logger = AppLogger.forTest();

    await CrashDetector.runOnce(heartbeatFile: file, logger: logger);

    final entries = logger.snapshot(category: LogCategory.lifecycle);
    expect(entries.single.level, LogLevel.info);
    expect(entries.single.message, contains('cleanly'));
    dir.deleteSync(recursive: true);
  });

  test('state=detached -> warn log', () async {
    final dir = _tempDir();
    final file = File('${dir.path}/heartbeat.json');
    await file.writeAsString(jsonEncode({'state': 'detached', 'route': '/'}));
    final logger = AppLogger.forTest();

    await CrashDetector.runOnce(heartbeatFile: file, logger: logger);

    final entries = logger.snapshot(category: LogCategory.lifecycle);
    expect(entries.single.level, LogLevel.warn);
    expect(entries.single.message, contains('detached'));
    dir.deleteSync(recursive: true);
  });
}
