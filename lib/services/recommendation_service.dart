import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/recommendation.dart';
import '../models/series.dart';
import 'foundation_models_channel.dart';
import 'recommendation_context_builder.dart';
import '../models/recommendation_context.dart';

class RecommendationCache {
  static const _kPickKey = 'ai_rec_daily_pick_json';
  static const _kDateKey = 'ai_rec_daily_date';

  final SharedPreferences _prefs;
  final Set<String> _sessionExclusions = {};
  final Set<String> _sessionTitles = {};

  /// Picks are per source: a pick names a series id on one server, and the
  /// card builds its cover URL with the active source.
  final String _suffix;

  RecommendationCache(this._prefs, {String sourceId = ''})
      : _suffix = sourceId.isEmpty ? '' : ':$sourceId';

  String get _pickKey => '$_kPickKey$_suffix';
  String get _dateKey => '$_kDateKey$_suffix';

  String _dateString(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Recommendation? readCachedPick({required DateTime today}) {
    final cachedDate = _prefs.getString(_dateKey);
    if (cachedDate != _dateString(today)) return null;
    final raw = _prefs.getString(_pickKey);
    if (raw == null) return null;
    try {
      return Recommendation.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> writeDailyPick(
    Recommendation rec, {
    required DateTime today,
  }) async {
    await _prefs.setString(_pickKey, jsonEncode(rec.toJson()));
    await _prefs.setString(_dateKey, _dateString(today));
  }

  Set<String> sessionExclusions() => Set.unmodifiable(_sessionExclusions);
  Set<String> sessionTitles() => Set.unmodifiable(_sessionTitles);

  void addSessionExclusion(String id) {
    _sessionExclusions.add(id);
  }

  void addSessionTitle(String title) {
    _sessionTitles.add(title);
  }

  void clearSessionExclusions() {
    _sessionExclusions.clear();
    _sessionTitles.clear();
  }
}

class SignalSnapshot {
  final List<Series> completedSeries;
  final List<InProgressEntry> inProgress;
  final List<String> topGenres;
  final List<String> topPublishers;
  final List<SessionEntry> sessions;
  final List<Series> unreadLibrary;

  /// True when signals were built from a first-launch timeout fallback
  /// (library never emitted). A pick generated from this snapshot must NOT
  /// be persisted — it is zero-signal and would poison the day-one cache.
  final bool isTimeoutFallback;

  const SignalSnapshot({
    required this.completedSeries,
    required this.inProgress,
    required this.topGenres,
    required this.topPublishers,
    required this.sessions,
    required this.unreadLibrary,
    this.isTimeoutFallback = false,
  });

  factory SignalSnapshot.empty() => const SignalSnapshot(
        completedSeries: [],
        inProgress: [],
        topGenres: [],
        topPublishers: [],
        sessions: [],
        unreadLibrary: [],
      );

  factory SignalSnapshot.timeoutFallback() => const SignalSnapshot(
        completedSeries: [],
        inProgress: [],
        topGenres: [],
        topPublishers: [],
        sessions: [],
        unreadLibrary: [],
        isTimeoutFallback: true,
      );
}

typedef SignalsLoader = Future<SignalSnapshot> Function();
typedef LibraryLookup = Series? Function(String seriesId);

class RecommendationService {
  final RecommendationCache cache;
  final FoundationModelsChannel channel;
  final SignalsLoader signalsLoader;
  final LibraryLookup libraryLookup;
  final DateTime Function() now;

  RecommendationService({
    required this.cache,
    required this.channel,
    required this.signalsLoader,
    required this.libraryLookup,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;

  Future<Recommendation?> getDailyPick({bool force = false}) async {
    if (!force) {
      final cached = cache.readCachedPick(today: now());
      if (cached != null) return cached;
    }
    if (!await channel.isAvailable()) return null;

    final signals = await signalsLoader();
    final ctx = RecommendationContextBuilder.build(
      completedSeries: signals.completedSeries,
      inProgress: signals.inProgress,
      topGenres: signals.topGenres,
      topPublishers: signals.topPublishers,
      sessions: signals.sessions,
      unreadLibrary: signals.unreadLibrary,
      excludedIds: cache.sessionExclusions(),
      avoidTitles: cache.sessionTitles().toList(),
    );

    final raw = await channel.recommend(ctx.toJson());
    final claimedId = raw['series_id'] as String?;
    final inLib = claimedId != null && libraryLookup(claimedId) != null;
    final rec = Recommendation(
      seriesId: inLib ? claimedId : null,
      title: raw['title'] as String,
      creator: raw['creator'] as String?,
      reasoning: raw['reasoning'] as String? ?? '',
      isInLibrary: inLib,
    );
    // Don't cache a pick generated from zero-signal timeout fallback — the
    // library hadn't synced yet, so this pick is generic. On the next app
    // launch (or when the provider invalidates) we'll have real signals.
    if (!signals.isTimeoutFallback) {
      await cache.writeDailyPick(rec, today: now());
    }
    return rec;
  }

  Future<Recommendation?> reroll() async {
    final current = cache.readCachedPick(today: now());
    if (current != null) {
      cache.addSessionTitle(current.title);
      if (current.seriesId != null) {
        cache.addSessionExclusion(current.seriesId!);
      }
    }
    return getDailyPick(force: true);
  }
}
