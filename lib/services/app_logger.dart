import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

enum LogLevel { debug, info, warn, error }
enum LogCategory { http, connectivity, reader, sync, memory, lifecycle, error }

class LogEvent {
  final DateTime timestamp;
  final LogLevel level;
  final LogCategory category;
  final String message;
  final Map<String, Object?> context;

  LogEvent({
    required this.timestamp,
    required this.level,
    required this.category,
    required this.message,
    this.context = const {},
  });

  Map<String, Object?> toJson() => {
        'ts': timestamp.toIso8601String(),
        'level': level.name,
        'category': category.name,
        'message': message,
        if (context.isNotEmpty) 'context': context,
      };

  factory LogEvent.fromJson(Map<String, Object?> j) => LogEvent(
        timestamp: DateTime.parse(j['ts'] as String),
        level: LogLevel.values.byName(j['level'] as String),
        category: LogCategory.values.byName(j['category'] as String),
        message: j['message'] as String,
        context: (j['context'] as Map?)?.cast<String, Object?>() ?? const {},
      );

  String toLine() => jsonEncode(toJson());
}

class AppLogger {
  AppLogger._({
    required int bufferCap,
    Directory? logDir,
    int fileSizeCap = 1024 * 1024,
  })  : _bufferCap = bufferCap,
        _logDir = logDir,
        _fileSizeCap = fileSizeCap;

  static AppLogger? _instance;
  static AppLogger get instance {
    final i = _instance;
    if (i == null) {
      throw StateError('AppLogger.init() must be called before instance');
    }
    return i;
  }

  /// Null before [init]. For paths that must not fail just because logging
  /// isn't up yet (e.g. recovery code running before app bootstrap).
  static AppLogger? get instanceOrNull => _instance;

  static AppLogger forTest({
    int bufferCap = 500,
    Directory? logDir,
    int fileSizeCap = 1024 * 1024,
  }) =>
      AppLogger._(
        bufferCap: bufferCap,
        logDir: logDir,
        fileSizeCap: fileSizeCap,
      );

  final int _bufferCap;
  final Directory? _logDir;
  final int _fileSizeCap;
  final List<LogEvent> _buffer = [];
  final StreamController<LogEvent> _controller =
      StreamController<LogEvent>.broadcast();

  IOSink? _sink;
  int _fileSize = 0;
  Future<void> _pending = Future.value();

  File get _mainFile => File('${_logDir!.path}/app.log');
  File get _backupFile => File('${_logDir!.path}/app.log.1');

  Future<void> _openFile() async {
    if (_logDir == null) return;
    if (!_logDir.existsSync()) await _logDir.create(recursive: true);
    if (!_mainFile.existsSync()) await _mainFile.create();
    _fileSize = await _mainFile.length();
    _sink = _mainFile.openWrite(mode: FileMode.writeOnlyAppend);
  }

  @visibleForTesting
  Future<void> openForTest() => _openFile();

  @visibleForTesting
  Future<void> flushForTest() async {
    await _pending;
    await _sink?.flush();
  }

  @visibleForTesting
  Future<void> closeFileForTest() async {
    await _sink?.close();
    _sink = null;
  }

  void _append(LogEvent event) {
    _buffer.add(event);
    if (_buffer.length > _bufferCap) {
      _buffer.removeRange(0, _buffer.length - _bufferCap);
    }
    if (!_controller.isClosed) _controller.add(event);
    _scheduleWrite(event);
  }

  @visibleForTesting
  void appendForTest(LogEvent event) => _append(event);

  void _scheduleWrite(LogEvent event) {
    if (_sink == null) return;
    final line = '${event.toLine()}\n';
    final bytes = utf8.encode(line);
    _pending = _pending.then((_) async {
      try {
        _sink!.add(bytes);
        await _sink!.flush();
        _fileSize += bytes.length;
        if (_fileSize >= _fileSizeCap) await _rotate();
      } catch (e) {
        // Drop the event from the file; ring buffer already has it.
        // Best-effort: try to reopen so future writes can resume.
        await _reopenAfterError();
      }
    });
  }

  Future<void> _rotate() async {
    await _sink?.close();
    _sink = null;
    if (_backupFile.existsSync()) await _backupFile.delete();
    if (_mainFile.existsSync()) await _mainFile.rename(_backupFile.path);
    await _openFile();
  }

  Future<void> _reopenAfterError() async {
    try {
      await _sink?.close();
    } catch (_) {}
    _sink = null;
    try {
      await _openFile();
    } catch (_) {
      // Swallow — degraded to memory-only.
    }
  }

  void _log(LogLevel level, LogCategory category, String message,
      Map<String, Object?> context) {
    _append(LogEvent(
      timestamp: DateTime.now(),
      level: level,
      category: category,
      message: message,
      context: context,
    ));
  }

  List<LogEvent> snapshot({LogCategory? category, LogLevel? minLevel}) {
    final minIdx = minLevel == null ? 0 : LogLevel.values.indexOf(minLevel);
    return _buffer.where((e) {
      if (category != null && e.category != category) return false;
      if (minLevel != null && LogLevel.values.indexOf(e.level) < minIdx) {
        return false;
      }
      return true;
    }).toList(growable: false);
  }

  void http({
    required LogLevel level,
    required String message,
    Map<String, Object?> context = const {},
  }) =>
      _log(level, LogCategory.http, message, context);

  void connectivity({
    required LogLevel level,
    required String message,
    Map<String, Object?> context = const {},
  }) =>
      _log(level, LogCategory.connectivity, message, context);

  void reader({
    required LogLevel level,
    required String message,
    Map<String, Object?> context = const {},
  }) =>
      _log(level, LogCategory.reader, message, context);

  void sync({
    required LogLevel level,
    required String message,
    Map<String, Object?> context = const {},
  }) =>
      _log(level, LogCategory.sync, message, context);

  void memory({
    required LogLevel level,
    required String message,
    Map<String, Object?> context = const {},
  }) =>
      _log(level, LogCategory.memory, message, context);

  void lifecycle({
    required LogLevel level,
    required String message,
    Map<String, Object?> context = const {},
  }) =>
      _log(level, LogCategory.lifecycle, message, context);

  void error({
    required LogLevel level,
    required String message,
    Map<String, Object?> context = const {},
  }) =>
      _log(level, LogCategory.error, message, context);

  Stream<LogEvent> stream() => _controller.stream;

  Future<void> clear() async {
    _buffer.clear();
    await _pending;
    await _sink?.close();
    _sink = null;
    if (_logDir != null) {
      if (_mainFile.existsSync()) await _mainFile.delete();
      if (_backupFile.existsSync()) await _backupFile.delete();
      await _openFile();
    }
  }

  Future<String> exportAsText() async {
    await _pending;
    await _sink?.flush();
    final parts = <String>[];
    if (_logDir != null) {
      if (_backupFile.existsSync()) parts.add(await _backupFile.readAsString());
      if (_mainFile.existsSync()) parts.add(await _mainFile.readAsString());
    }
    if (parts.isEmpty) {
      parts.add(snapshot().map((e) => e.toLine()).join('\n'));
    }
    return parts.join();
  }

  /// Initialize the production singleton. Safe to call once at app startup.
  ///
  /// [logDirFactory] returns the directory where logs should be written.
  /// If it throws or returns null, the logger runs in memory-only mode.
  static Future<void> init({
    required Future<Directory?> Function() logDirFactory,
  }) async {
    if (_instance != null) return;
    Directory? dir;
    try {
      final base = await logDirFactory();
      if (base != null) {
        dir = Directory('${base.path}/logs');
        if (!dir.existsSync()) await dir.create(recursive: true);
      }
    } catch (_) {
      dir = null;
    }
    final logger = AppLogger._(bufferCap: 500, logDir: dir);
    if (dir != null) {
      try {
        await logger._openFile();
      } catch (_) {
        // Degraded mode — memory only.
      }
    }
    _instance = logger;
    logger.connectivity(
      level: LogLevel.info,
      message: dir == null
          ? 'AppLogger started in memory-only mode'
          : 'AppLogger started',
      context: {'logDir': dir?.path ?? 'none'},
    );
  }

  @visibleForTesting
  static void resetForTest() {
    _instance = null;
  }
}
