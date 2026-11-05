import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/local_stats.dart';
import '../models/series.dart';
import 'mirror_provider.dart';
import '../services/mirror/mirror_database.dart' show MirrorSeries;
import 'cache_providers.dart';
import '../models/reading_session.dart';
import '../models/stats_summary.dart';
import 'providers.dart';

final statsSummaryProvider =
    FutureProvider.autoDispose<StatsSummary>((ref) async {
  // Komga: sessions live on the device; names and covers from the mirror.
  if (!ref.watch(isCustomSourceProvider)) {
    final sessions = await ref.watch(localSessionStoreProvider)?.all() ?? [];
    final library = await ref.watch(mirrorLibraryProvider.future);
    return computeLocalStats(sessions, _byId(library), DateTime.now());
  }
  final client = ref.watch(apiClientProvider);
  return client.fetchStatsSummary();
});

Map<String, Series> _byId(List<MirrorSeries> library) =>
    {for (final m in library) m.series.id: m.series};

class StatsHistoryNotifier extends Notifier<StatsHistoryState> {
  @override
  StatsHistoryState build() {
    // Keeps the mirror library alive for local (Komga) history names.
    ref.listen(mirrorLibraryProvider, (_, _) {});
    // ponytail: _loadPage writes state, so it cannot run until build() returns.
    Future.microtask(() => _loadPage(1));
    return const StatsHistoryState();
  }

  Future<void> _loadPage(int page) async {
    state = state.copyWith(loading: true);
    try {
      final result = ref.read(isCustomSourceProvider)
          ? await ref.read(apiClientProvider).fetchStatsHistory(page: page, limit: 20)
          : localHistory(
              await ref.read(localSessionStoreProvider)?.all() ?? [],
              _byId(await ref.read(mirrorLibraryProvider.future)),
              page: page,
              limit: 20);
      state = state.copyWith(
        sessions: [...state.sessions, ...result.sessions],
        total: result.total,
        currentPage: page,
        loading: false,
      );
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  void loadMore() {
    if (state.loading || state.sessions.length >= state.total) return;
    _loadPage(state.currentPage + 1);
  }

  Future<void> refresh() async {
    state = const StatsHistoryState();
    await _loadPage(1);
  }
}

class StatsHistoryState {
  final List<ReadingSession> sessions;
  final int total;
  final int currentPage;
  final bool loading;
  final String? error;

  const StatsHistoryState({
    this.sessions = const [],
    this.total = 0,
    this.currentPage = 0,
    this.loading = false,
    this.error,
  });

  StatsHistoryState copyWith({
    List<ReadingSession>? sessions,
    int? total,
    int? currentPage,
    bool? loading,
    String? error,
  }) {
    return StatsHistoryState(
      sessions: sessions ?? this.sessions,
      total: total ?? this.total,
      currentPage: currentPage ?? this.currentPage,
      loading: loading ?? this.loading,
      error: error,
    );
  }

  bool get hasMore => sessions.length < total;
}

final statsHistoryProvider =
    NotifierProvider.autoDispose<StatsHistoryNotifier, StatsHistoryState>(
        StatsHistoryNotifier.new);
