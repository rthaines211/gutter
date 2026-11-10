import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/source_urls.dart';
import '../models/server_source.dart';
import '../services/source_auth_client.dart';
import 'package:path/path.dart' as p;

import '../services/mirror/cover_syncer.dart';
import '../services/mirror/mirror_database.dart';
import '../services/mirror/sync_engine.dart';
import '../services/mirror/sync_progress.dart';
import 'cache_providers.dart';
import 'providers.dart';
import 'source_provider.dart';

/// One mirror database per server source. Kept alive for the app's lifetime
/// (switching sources swaps the database file).
final mirrorDbProvider = Provider<MirrorDatabase>((ref) {
  // Only the id names the file. Watching the whole source reopened the
  // database on every address or login edit and failed any sync in flight
  // ("Channel was closed before receiving a response").
  final id = ref.watch(activeSourceProvider.select((s) => s.id));
  final db = MirrorDatabase.open(id);
  ref.onDispose(db.close);
  return db;
});

/// Permanent cover storage for the active source.
final coversDirProvider = Provider<String?>((ref) {
  final docsDir = ref.watch(docsDirProvider).value;
  if (docsDir == null) return null;
  final source = ref.watch(activeSourceProvider);
  return p.join(docsDir, 'covers', source.id);
});

/// What the active source's mirror sync is doing (sync_progress_view.dart).
final syncProgressProvider =
    NotifierProvider<SyncProgressNotifier, SyncProgress>(
        SyncProgressNotifier.new);

class SyncProgressNotifier extends Notifier<SyncProgress> {
  @override
  SyncProgress build() {
    ref.watch(activeSourceProvider.select((s) => s.id));
    return const SyncProgress();
  }

  void apply(SyncProgress Function(SyncProgress) update) =>
      state = update(state);
}

SyncProgressUpdate _progressSink(Ref ref) =>
    (update) {
      if (ref.mounted) ref.read(syncProgressProvider.notifier).apply(update);
    };

final syncEngineProvider = Provider<SyncEngine?>((ref) {
  final queue = ref.watch(syncQueueProvider);
  if (queue == null) return null;
  return SyncEngine(
    db: ref.watch(mirrorDbProvider),
    client: ref.watch(apiClientProvider),
    queue: queue,
    // Each Komga or Kavita pull re-reads the whole library.
    minPullInterval: ref.watch(activeSourceProvider).type != SourceType.custom
        ? const Duration(minutes: 10)
        : Duration.zero,
    onProgress: _progressSink(ref),
  );
});

final coverSyncerProvider = Provider<CoverSyncer?>((ref) {
  final dir = ref.watch(coversDirProvider);
  if (dir == null) return null;
  final source = ref.watch(activeSourceProvider);
  return CoverSyncer(
    db: ref.watch(mirrorDbProvider),
    baseUrl: source.baseUrl,
    headers: source.authHeaders,
    coversDir: dir,
    httpClient: SourceAuthClient(),
    onProgress: _progressSink(ref),
  );
});

/// Unfiltered mirrored library — base stream for libraryProvider, facets,
/// and home shelves.
final mirrorLibraryProvider = StreamProvider<List<MirrorSeries>>((ref) {
  return ref.watch(mirrorDbProvider).watchLibrary();
});

/// Synced cover path per issue id ([MirrorDatabase.watchIssueCoverPaths]);
/// empty for sources without a mirror (OPDS).
final issueCoverPathsProvider = StreamProvider<Map<String, String>>((ref) {
  if (!ref.watch(hasMirrorProvider)) return Stream.value(const {});
  return ref.watch(mirrorDbProvider).watchIssueCoverPaths();
});

/// An issue's cover URL. Uses the synced, versioned path when the mirror has
/// one, so a cover the server changed is fetched again instead of served from
/// the image cache; otherwise builds it from the id. Every issue cover goes
/// through here.
final issueCoverUrlProvider = Provider.family<String, String>((ref, comicId) {
  final source = ref.watch(activeSourceProvider);
  final path = ref.watch(issueCoverPathsProvider).value?[comicId];
  if (path == null || path.isEmpty) return source.comicCover(comicId);
  return path.startsWith('http') ? path : '${source.baseUrl}$path';
});
