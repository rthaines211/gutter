import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/recommendation.dart';
import '../models/recommendation_context.dart';
import '../models/series.dart';
import '../services/foundation_models_channel.dart';
import '../services/recommendation_service.dart';
import '../models/reading_progress.dart';
import 'library_provider.dart';
import 'mirror_provider.dart';
import 'providers.dart';
import 'source_provider.dart';
import 'stats_provider.dart';

final recommendationCacheProvider = Provider<RecommendationCache>((ref) {
  final cache = RecommendationCache(ref.watch(sharedPrefsProvider),
      sourceId: ref.watch(activeSourceProvider.select((s) => s.id)));
  cache.clearSessionExclusions();
  return cache;
});

final foundationModelsChannelProvider = Provider<FoundationModelsChannel>(
  (ref) => FoundationModelsChannel(),
);

final recommendationSignalsLoaderProvider = Provider<SignalsLoader>((ref) {
  return () async {
    // On a true first launch (empty mirror, never synced) libraryProvider
    // suppresses emissions until the first sync completes, so this future may
    // never resolve. Time out and fall back to an empty library so
    // recommendations degrade gracefully instead of hanging forever.
    bool libraryTimedOut = false;
    final library = await ref
        .read(libraryProvider.future)
        .timeout(const Duration(seconds: 15), onTimeout: () {
      libraryTimedOut = true;
      return <Series>[];
    });
    // Continue-reading comes from the on-device mirror, not the network.
    // Same defensive timeout as the library signal: degrade to empty rather
    // than hang if the stream never emits.
    final reading = await ref
        .read(mirrorDbProvider)
        .watchReadingList()
        .first
        .timeout(const Duration(seconds: 15),
            onTimeout: () => <ReadingProgress>[]);
    final stats = await ref.read(statsSummaryProvider.future);

    final completed = library.where((s) => s.isCompleted).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    final unread = library.where((s) => s.isUnread || s.isInProgress).toList();

    final byId = {for (final s in library) s.id: s};
    final inProgress = <InProgressEntry>[];
    for (final p in reading) {
      final id = p.seriesId;
      if (id == null) continue;
      final series = byId[id];
      if (series == null) continue;
      final pct = p.totalPages > 0
          ? ((p.currentPage / p.totalPages) * 100).round()
          : 0;
      inProgress.add(InProgressEntry(name: series.name, progressPct: pct));
    }

    return SignalSnapshot(
      completedSeries: completed,
      inProgress: inProgress,
      topGenres: stats.topGenres.map((e) => e.name).toList(),
      topPublishers: stats.topPublishers.map((e) => e.name).toList(),
      // Sessions from stats history not yet wired — follow-up task needed
      sessions: const [],
      unreadLibrary: unread,
      isTimeoutFallback: libraryTimedOut,
    );
  };
});

final recommendationLibraryLookupProvider = Provider<LibraryLookup>((ref) {
  return (id) {
    final lib = ref.read(libraryProvider).value ?? const <Series>[];
    for (final s in lib) {
      if (s.id == id) return s;
    }
    return null;
  };
});

final recommendationServiceProvider = Provider<RecommendationService>((ref) {
  final channel = ref.watch(foundationModelsChannelProvider);
  channel.prewarm();
  return RecommendationService(
    cache: ref.watch(recommendationCacheProvider),
    channel: channel,
    signalsLoader: ref.watch(recommendationSignalsLoaderProvider),
    libraryLookup: ref.watch(recommendationLibraryLookupProvider),
  );
});

class RecommendationNotifier extends AsyncNotifier<Recommendation?> {
  @override
  Future<Recommendation?> build() async {
    final service = ref.watch(recommendationServiceProvider);
    return service.getDailyPick();
  }

  Future<void> reroll() async {
    state = const AsyncLoading();
    final service = ref.read(recommendationServiceProvider);
    state = await AsyncValue.guard(() => service.reroll());
  }

  void clear() {
    ref.invalidateSelf();
  }
}

final recommendationProvider =
    AsyncNotifierProvider<RecommendationNotifier, Recommendation?>(
        RecommendationNotifier.new);
