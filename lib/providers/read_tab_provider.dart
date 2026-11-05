import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rxdart/rxdart.dart';
import '../models/library_filter.dart';
import '../models/reading_progress.dart';
import '../models/series.dart';
import '../models/stats_summary.dart';
import '../services/mirror/library_view.dart';
import '../services/mirror/mirror_database.dart';
import 'mirror_provider.dart';
import 'providers.dart';

class ReadTabData {
  final List<ReadingProgress> continueReading;
  final List<Series> recentSeries;
  final StatsSummary? stats;

  const ReadTabData({
    required this.continueReading,
    required this.recentSeries,
    this.stats,
  });

  ReadingProgress? get heroProgress =>
      continueReading.isNotEmpty ? continueReading.first : null;

  List<ReadingProgress> get upNext =>
      continueReading.length > 1 ? continueReading.sublist(1) : [];

  List<Series> get justAdded => recentSeries
      .where((s) => s.isUnread && s.isRecentlyAdded)
      .take(8)
      .toList();
}

final readTabProvider = StreamProvider.autoDispose<ReadTabData>((ref) {
  final db = ref.watch(mirrorDbProvider);
  final client = ref.watch(apiClientProvider);

  // Stats stay network-only (out of mirror scope): emit null immediately so
  // the shelves render from the mirror, then patch stats in when they load.
  final stats$ = Stream.fromFuture(
    client
        .fetchStatsSummary()
        .then<StatsSummary?>((s) => s)
        .catchError((_) => null),
  ).startWith(null);

  return Rx.combineLatest3(
    db.watchReadingList(),
    db.watchLibrary(),
    stats$,
    (List<ReadingProgress> reading, List<MirrorSeries> lib,
            StatsSummary? stats) =>
        (reading: reading, lib: lib, stats: stats),
  )
      .asyncMap((d) async {
        // Very first launch: the mirror is empty because the initial sync
        // hasn't completed. Suppress the emission so the tab stays in its
        // loading state instead of flashing "No comics in progress".
        if (d.reading.isEmpty &&
            d.lib.isEmpty &&
            await db.getSyncState('last_server_time') == null) {
          return null;
        }
        return ReadTabData(
          continueReading: d.reading,
          recentSeries: applyLibraryFilter(
              d.lib, const LibraryFilter(sort: 'recent', order: 'desc')),
          stats: d.stats,
        );
      })
      .where((r) => r != null)
      .cast<ReadTabData>();
});
