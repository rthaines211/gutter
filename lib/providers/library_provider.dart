import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/library_filter.dart';
import '../models/series.dart';
import '../models/server_source.dart';
import '../services/mirror/library_view.dart';
import '../services/opds_client.dart';
import 'download_provider.dart';
import 'mirror_provider.dart';
import 'providers.dart';
import 'source_provider.dart';

class LibraryFilterNotifier extends Notifier<LibraryFilter> {
  @override
  LibraryFilter build() => const LibraryFilter();

  void setSort(String sort) => state = state.copyWith(sort: sort);
  void setOrder(String order) => state = state.copyWith(order: order);
  void setStatus(String status) => state = state.copyWith(status: status);
  void setQuery(String query) => state = state.copyWith(query: query);

  void setPublisher(String? publisher) => state = publisher == null
      ? state.copyWith(clearPublisher: true)
      : state.copyWith(publisher: publisher);

  void setGenre(String? genre) => state = genre == null
      ? state.copyWith(clearGenre: true)
      : state.copyWith(genre: genre);

  void setWriter(String? writer) => state = writer == null
      ? state.copyWith(clearWriter: true)
      : state.copyWith(writer: writer);

  void setPenciller(String? penciller) => state = penciller == null
      ? state.copyWith(clearPenciller: true)
      : state.copyWith(penciller: penciller);

  void setYearRange(int? min, int? max) {
    var updated = state;
    if (min == null) {
      updated = updated.copyWith(clearYearMin: true);
    } else {
      updated = updated.copyWith(yearMin: min);
    }
    if (max == null) {
      updated = updated.copyWith(clearYearMax: true);
    } else {
      updated = updated.copyWith(yearMax: max);
    }
    state = updated;
  }

  void clearMetadataFilters() => state = state.copyWith(
        clearPublisher: true,
        clearGenre: true,
        clearWriter: true,
        clearPenciller: true,
        clearYearMin: true,
        clearYearMax: true,
      );

  void reset() => state = const LibraryFilter();
}

final libraryFilterProvider =
    NotifierProvider<LibraryFilterNotifier, LibraryFilter>(
        LibraryFilterNotifier.new);

/// Library straight from the on-device mirror — instant, online or offline.
/// Filtering/sorting is local (services/mirror/library_view.dart); the
/// SyncEngine keeps the mirror current in the background.
final libraryProvider = StreamProvider.autoDispose<List<Series>>((ref) {
  final db = ref.watch(mirrorDbProvider);
  final filter = ref.watch(libraryFilterProvider);
  // Watched only for the "On iPad" view, so download progress doesn't
  // re-run the library query otherwise.
  final onDevice = filter.status == 'on_device'
      ? ref.watch(onDeviceProvider).perSeries.keys.toSet()
      : null;
  return db
      .watchLibrary()
      .asyncMap((all) async {
        // Very first launch: the mirror is empty because the initial sync
        // hasn't completed. Suppress the emission so the screen stays in its
        // loading state instead of flashing "empty library".
        if (all.isEmpty &&
            await db.getSyncState('last_server_time') == null) {
          return null;
        }
        return applyLibraryFilter(all, filter, onDevice: onDevice);
      })
      .where((result) => result != null)
      .cast<List<Series>>();
});

final seriesDetailProvider =
    StreamProvider.autoDispose.family<SeriesDetail, String>((ref, seriesId) {
  final db = ref.watch(mirrorDbProvider);
  return db.watchSeriesDetail(seriesId).map((detail) {
    if (detail == null) {
      throw Exception('Series not in local mirror: $seriesId');
    }
    return detail;
  });
});

class LibraryViewModeNotifier extends Notifier<String> {
  @override
  String build() {
    final prefs = ref.watch(sharedPrefsProvider);
    return prefs.getString('library_view_mode') ?? 'grid';
  }

  void toggle() {
    final newMode = state == 'grid' ? 'list' : 'grid';
    state = newMode;
    ref.read(sharedPrefsProvider).setString('library_view_mode', newMode);
  }
}

final libraryViewModeProvider =
    NotifierProvider<LibraryViewModeNotifier, String>(
  LibraryViewModeNotifier.new,
);

/// Active smart filter selection for the library.
/// 'all' = no filter, 'smart:`<id>`' = specific smart filter.
class LibrarySmartFilterNotifier extends Notifier<String> {
  @override
  String build() => 'all';

  void select(int filterId) => state = 'smart:$filterId';
  void clear() => state = 'all';
}

final librarySmartFilterProvider =
    NotifierProvider<LibrarySmartFilterNotifier, String>(
  LibrarySmartFilterNotifier.new,
);

/// Fetches the root OPDS catalog and converts entries to Series objects
/// for display in the library grid.
final opdsLibraryProvider =
    FutureProvider.autoDispose<List<Series>>((ref) async {
  final source = ref.watch(activeSourceProvider);
  if (source.type != SourceType.opds) return [];

  final client = OPDSClient(source: source);
  final feed = await client.fetchRoot();

  // OPDS root is typically navigation — find the first acquisition-type subsection
  // and fetch it to get actual series/comics
  for (final entry in feed.entries) {
    if (entry.navigationLink != null) {
      final subFeed = await client.fetchFeed(entry.navigationLink!);
      return subFeed.entries.map((e) => Series(
        id: e.id,
        name: e.title,
        folderPath: '',
        issueCount: 0,
        readCount: 0,
        coverUrl: e.thumbnailUrl != null
            ? client.resolveThumbnailUrl(e.thumbnailUrl!)
            : '',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      )).toList();
    }
  }

  // If root is already acquisition entries, convert directly
  return feed.entries.map((e) => Series(
    id: e.id,
    name: e.title,
    folderPath: '',
    issueCount: 0,
    readCount: 0,
    coverUrl: e.thumbnailUrl != null
        ? client.resolveThumbnailUrl(e.thumbnailUrl!)
        : '',
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  )).toList();
});
