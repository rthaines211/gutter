import '../models/stats_summary.dart';
import '../models/collection.dart';
import '../models/smart_filter.dart';
import 'api_client.dart';
import 'cache_layer.dart';
import 'app_logger.dart';

class CachedApi {
  final ApiClient client;
  final CacheLayer cache;
  bool _isOffline = false;

  CachedApi({required this.client, required this.cache});

  bool get isOffline => _isOffline;

  /// Pass-through for non-cached operations.
  ApiClient get raw => client;

  // ---------------------------------------------------------------------------
  // Generic helpers
  // ---------------------------------------------------------------------------

  /// Generic cache-through helper.
  Future<T> _withCache<T>({
    required String key,
    required Future<T> Function() fetch,
    required dynamic Function(T) toJson,
    required T Function(dynamic) fromJson,
  }) async {
    try {
      final result = await fetch();
      _isOffline = false;
      await cache.write(key, toJson(result));
      AppLogger.instance.http(
        level: LogLevel.debug,
        message: 'cached: network hit',
        context: {'key': key, 'source': 'network'},
      );
      return result;
    } catch (e) {
      final cached = await cache.read(key);
      if (cached != null) {
        _isOffline = true;
        AppLogger.instance.http(
          level: LogLevel.warn,
          message: 'cached: fell back to cache',
          context: {'key': key, 'source': 'cache', 'error': e.toString()},
        );
        return fromJson(cached['data']);
      }
      AppLogger.instance.http(
        level: LogLevel.error,
        message: 'cached: no cache, rethrowing',
        context: {'key': key, 'error': e.toString()},
      );
      rethrow;
    }
  }

  /// Generic fallback for non-critical endpoints.
  Future<List<T>> _withFallback<T>({
    required Future<List<T>> Function() fetch,
  }) async {
    try {
      final result = await fetch();
      _isOffline = false;
      return result;
    } catch (e) {
      AppLogger.instance.http(
        level: LogLevel.warn,
        message: 'fallback: returning empty list',
        context: {'error': e.toString()},
      );
      return [];
    }
  }

  // ---------------------------------------------------------------------------
  // Write-through cached endpoints
  // ---------------------------------------------------------------------------

  // fetchLibrary / fetchSeriesDetail / getReadingList were removed: the drift
  // mirror (lib/services/mirror/) is now the source of truth for library and
  // reading-list data, and series detail goes through ApiClient directly.

  Future<StatsSummary> fetchStatsSummary() => _withCache(
        key: 'stats_summary',
        fetch: () => client.fetchStatsSummary(),
        toJson: _statsSummaryToJson,
        fromJson: (data) =>
            StatsSummary.fromJson(data as Map<String, dynamic>),
      );

  // ---------------------------------------------------------------------------
  // Silent empty-list fallback (not critical offline)
  // ---------------------------------------------------------------------------

  Future<List<Collection>> fetchCollections() =>
      _withFallback(fetch: () => client.fetchCollections());

  Future<List<SmartFilter>> fetchSmartFilters() =>
      _withFallback(fetch: () => client.fetchSmartFilters());

  // ---------------------------------------------------------------------------
  // JSON serialization helpers (models lack toJson)
  // ---------------------------------------------------------------------------

  static Map<String, dynamic> _statsSummaryToJson(StatsSummary s) => {
        'all_time': _periodStatsToJson(s.allTime),
        'this_week': _periodStatsToJson(s.thisWeek),
        'this_month': _periodStatsToJson(s.thisMonth),
        'pages_per_day': s.pagesPerDay
            .map((d) => {'date': d.date, 'pages': d.pages})
            .toList(),
        'top_genres': s.topGenres
            .map((n) => {'name': n.name, 'count': n.count})
            .toList(),
        'top_publishers': s.topPublishers
            .map((n) => {'name': n.name, 'count': n.count})
            .toList(),
      };

  static Map<String, dynamic> _periodStatsToJson(PeriodStats p) => {
        'pages_read': p.pagesRead,
        'issues_finished': p.issuesFinished,
        'series_completed': p.seriesCompleted,
        'time_read_s': p.timeReadS,
      };
}
