import 'package:flutter/widgets.dart';
import 'app_logger.dart';

typedef CacheStatsFn = ({int count, int bytes}) Function();
typedef CacheClearFn = void Function();

class MemoryPressureWatcher with WidgetsBindingObserver {
  MemoryPressureWatcher({
    AppLogger? logger,
    CacheStatsFn? cacheStats,
    CacheClearFn? onClear,
  })  : _logger = logger,
        _cacheStats = cacheStats ?? _defaultStats,
        _onClear = onClear ?? _defaultClear;

  final AppLogger? _logger;
  final CacheStatsFn _cacheStats;
  final CacheClearFn _onClear;

  AppLogger get _log => _logger ?? AppLogger.instance;

  void init() {
    WidgetsBinding.instance.addObserver(this);
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didHaveMemoryPressure() {
    final stats = _cacheStats();
    try {
      _onClear();
    } catch (_) {
      // Swallow — diagnostic plumbing must never become a crash source.
    }
    _log.memory(
      level: LogLevel.warn,
      message: 'iOS memory pressure: image cache cleared',
      context: {
        'beforeCount': stats.count,
        'beforeBytes': stats.bytes,
      },
    );
  }

  static ({int count, int bytes}) _defaultStats() {
    final c = PaintingBinding.instance.imageCache;
    return (count: c.currentSize, bytes: c.currentSizeBytes);
  }

  static void _defaultClear() {
    final c = PaintingBinding.instance.imageCache;
    c.clear();
    c.clearLiveImages();
  }
}
