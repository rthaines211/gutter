import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/services/app_logger.dart';

LogEvent _evt({
  LogLevel level = LogLevel.info,
  LogCategory category = LogCategory.http,
  String message = 'm',
  Map<String, Object?> context = const {},
}) =>
    LogEvent(
      timestamp: DateTime.now(),
      level: level,
      category: category,
      message: message,
      context: context,
    );

void main() {
  group('AppLogger ring buffer', () {
    test('snapshot returns events in insertion order', () {
      final logger = AppLogger.forTest();
      logger.appendForTest(_evt(message: 'a'));
      logger.appendForTest(_evt(message: 'b'));
      logger.appendForTest(_evt(message: 'c'));

      final events = logger.snapshot();
      expect(events.map((e) => e.message).toList(), ['a', 'b', 'c']);
    });

    test('snapshot caps at 500 and drops oldest', () {
      final logger = AppLogger.forTest();
      for (var i = 0; i < 600; i++) {
        logger.appendForTest(_evt(message: 'm$i'));
      }
      final events = logger.snapshot();
      expect(events.length, 500);
      expect(events.first.message, 'm100');
      expect(events.last.message, 'm599');
    });

    test('snapshot filters by category', () {
      final logger = AppLogger.forTest();
      logger.appendForTest(_evt(category: LogCategory.http, message: 'h'));
      logger.appendForTest(_evt(category: LogCategory.reader, message: 'r'));
      logger.appendForTest(_evt(category: LogCategory.http, message: 'h2'));

      final http = logger.snapshot(category: LogCategory.http);
      expect(http.map((e) => e.message).toList(), ['h', 'h2']);
    });

    test('snapshot filters by minLevel', () {
      final logger = AppLogger.forTest();
      logger.appendForTest(_evt(level: LogLevel.debug, message: 'd'));
      logger.appendForTest(_evt(level: LogLevel.info, message: 'i'));
      logger.appendForTest(_evt(level: LogLevel.warn, message: 'w'));
      logger.appendForTest(_evt(level: LogLevel.error, message: 'e'));

      final warns = logger.snapshot(minLevel: LogLevel.warn);
      expect(warns.map((e) => e.message).toList(), ['w', 'e']);
    });

    test('clear empties the buffer', () async {
      final logger = AppLogger.forTest();
      logger.appendForTest(_evt(message: 'a'));
      await logger.clear();
      expect(logger.snapshot(), isEmpty);
    });
  });

  group('AppLogger stream', () {
    test('stream emits events appended after subscription', () async {
      final logger = AppLogger.forTest();
      final received = <String>[];
      final sub = logger.stream().listen((e) => received.add(e.message));

      logger.appendForTest(_evt(message: 'one'));
      logger.appendForTest(_evt(message: 'two'));
      await Future<void>.delayed(Duration.zero);

      expect(received, ['one', 'two']);
      await sub.cancel();
    });

    test('stream does NOT replay events from before subscription', () async {
      final logger = AppLogger.forTest();
      logger.appendForTest(_evt(message: 'past'));

      final received = <String>[];
      final sub = logger.stream().listen((e) => received.add(e.message));
      logger.appendForTest(_evt(message: 'after'));
      await Future<void>.delayed(Duration.zero);

      expect(received, ['after']);
      await sub.cancel();
    });
  });

  group('AppLogger file backend', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('app_logger_test');
    });

    tearDown(() async {
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    });

    test('events are appended as JSON lines to app.log', () async {
      final logger = AppLogger.forTest(logDir: tempDir);
      await logger.openForTest();
      logger.appendForTest(_evt(message: 'first'));
      logger.appendForTest(_evt(message: 'second'));
      await logger.flushForTest();

      final file = File('${tempDir.path}/app.log');
      expect(file.existsSync(), isTrue);
      final lines = await file.readAsLines();
      expect(lines.length, 2);
      expect(jsonDecode(lines[0])['message'], 'first');
      expect(jsonDecode(lines[1])['message'], 'second');
    });

    test('rotates app.log to app.log.1 when over the size cap', () async {
      final logger = AppLogger.forTest(logDir: tempDir, fileSizeCap: 200);
      await logger.openForTest();

      // Big context payloads to cross 200 bytes quickly.
      for (var i = 0; i < 6; i++) {
        logger.appendForTest(_evt(
          message: 'm$i',
          context: {'pad': 'x' * 40},
        ));
        await logger.flushForTest();
      }

      final main = File('${tempDir.path}/app.log');
      final backup = File('${tempDir.path}/app.log.1');
      expect(main.existsSync(), isTrue);
      expect(backup.existsSync(), isTrue);
      expect(main.lengthSync(), lessThan(200));
    });

    test('write error is swallowed and ring buffer is unaffected', () async {
      // Close the log file out from under the logger to force a write error.
      final logger = AppLogger.forTest(logDir: tempDir);
      await logger.openForTest();
      await logger.closeFileForTest();

      // Appending must not throw.
      expect(
        () => logger.appendForTest(_evt(message: 'survives')),
        returnsNormally,
      );
      expect(logger.snapshot().last.message, 'survives');
    });
  });

  group('AppLogger category methods', () {
    test('accepts memory, lifecycle, and error categories', () {
      final logger = AppLogger.forTest();
      logger.memory(level: LogLevel.warn, message: 'mem');
      logger.lifecycle(level: LogLevel.info, message: 'state=resumed');
      logger.error(level: LogLevel.error, message: 'boom');

      List<String> byCat(LogCategory c) =>
          logger.snapshot(category: c).map((e) => e.message).toList();
      expect(byCat(LogCategory.memory), ['mem']);
      expect(byCat(LogCategory.lifecycle), ['state=resumed']);
      expect(byCat(LogCategory.error), ['boom']);
    });

    test('http() builds a LogEvent in the http category', () async {
      final logger = AppLogger.forTest();
      logger.http(
        level: LogLevel.warn,
        message: 'slow',
        context: {'durationMs': 9000},
      );
      final last = logger.snapshot().last;
      expect(last.category, LogCategory.http);
      expect(last.level, LogLevel.warn);
      expect(last.context['durationMs'], 9000);
    });

    test('connectivity/reader/sync helpers tag the right category', () {
      final logger = AppLogger.forTest();
      logger.connectivity(level: LogLevel.info, message: 'c');
      logger.reader(level: LogLevel.info, message: 'r');
      logger.sync(level: LogLevel.info, message: 's');
      final s = logger.snapshot();
      expect(s.map((e) => e.category).toList(), [
        LogCategory.connectivity,
        LogCategory.reader,
        LogCategory.sync,
      ]);
    });
  });

  group('AppLogger export', () {
    late Directory tempDir;
    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('app_logger_export');
    });
    tearDown(() async {
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    });

    test('exportAsText concatenates rotated file and current buffer', () async {
      final logger = AppLogger.forTest(logDir: tempDir);
      await logger.openForTest();
      logger.http(level: LogLevel.info, message: 'one');
      logger.http(level: LogLevel.info, message: 'two');
      await logger.flushForTest();

      final text = await logger.exportAsText();
      expect(text, contains('"message":"one"'));
      expect(text, contains('"message":"two"'));
    });
  });
}
