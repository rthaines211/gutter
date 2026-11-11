import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../models/download_item.dart';
import '../models/series.dart';
import '../models/server_source.dart';
import '../services/page_fetcher.dart';
import '../services/download_manager.dart';
import '../services/mirror/cover_syncer.dart' show evictCover;
import 'mirror_provider.dart';
import 'providers.dart';
import 'source_provider.dart';
import 'cache_providers.dart';

/// Provides the app documents directory path.
final _docsDirProvider = FutureProvider<String>((ref) async {
  final dir = await getApplicationDocumentsDirectory();
  return dir.path;
});

/// Provides the DownloadManager instance, initialized with the documents directory.
final downloadManagerProvider = Provider<DownloadManager?>((ref) {
  final docsDir = ref.watch(_docsDirProvider).value;
  if (docsDir == null) return null;
  final client = http.Client();
  late final DownloadManager manager;
  manager = DownloadManager(
    baseDir: docsDir,
    httpClient: client,
    // Keeps downloading while the app is suspended.
    fetcher: BackgroundFetcher(docsDir, client),
    authFor: (sourceId) {
      for (final s in ref.read(sourceListProvider)) {
        if (s.id == sourceId) return s.authHeaders;
      }
      return const {};
    },
    // A local source's library is what's on disk: list it again.
    onDeleted: (sourceId, seriesId) {
      if (!ref.mounted) return;
      final local = ref.read(sourceListProvider).any(
          (s) => s.id == sourceId && s.type == SourceType.local);
      if (!local) return;
      removeOrphanLocalCover(
          docsDir, sourceId, seriesId, manager.currentState.completed);
      if (ref.read(activeSourceProvider).id == sourceId) {
        ref.read(syncEngineProvider)?.sync(force: true).ignore();
      }
    },
  );
  ref.onDispose(() => manager.dispose());
  // Restores the queue journal and sweeps half-finished downloads.
  manager.init();
  // Now, and again when a server is added or the local source is set up.
  ref.listen(sourceListProvider,
      (_, sources) => applyBackupFlags(docsDir, sources),
      fireImmediately: true);
  return manager;
});

/// Free space on the device in bytes, or null where it can't be read (tests,
/// non-iOS).
Future<int?> deviceFreeBytes() async {
  try {
    return await const MethodChannel('app.comic_reader/files')
        .invokeMethod<int>('freeSpace');
  } catch (_) {
    return null;
  }
}

/// iCloud backup, per source: a server's downloads can be fetched again, so
/// its directory is excluded; comics imported into a local source exist
/// nowhere else, so its directory stays in. Installs before local sources
/// had the flag on the shared `downloads/` parent (which excludes everything
/// under it): it is cleared last, once every server directory has its own.
/// The flag lives on the directory, so this runs (idempotently) every launch.
/// ponytail: `downloads/queue.json` (the queue journal, no credentials) is
/// now backed up too.
@visibleForTesting
Future<void> applyBackupFlags(String docsDir, List<ServerSource> sources) async {
  const channel = MethodChannel('app.comic_reader/files');
  final root = p.join(docsDir, 'downloads');
  try {
    for (final s in sources) {
      final dir = p.join(root, s.id);
      await Directory(dir).create(recursive: true);
      await channel.invokeMethod('excludeFromBackup',
          {'path': dir, 'exclude': s.type != SourceType.local});
    }
    await channel
        .invokeMethod('excludeFromBackup', {'path': root, 'exclude': false});
  } catch (_) {
    // No handler (tests), or a directory failed: the parent keeps whatever
    // flag it had, so nothing a server gave us gets into the backup.
  }
}

/// Deletes a local series' cover file once [completed] (the comics still on
/// the device) holds none of its issues.
@visibleForTesting
void removeOrphanLocalCover(String docsDir, String sourceId, String seriesId,
    List<DownloadItem> completed) {
  if (seriesId.isEmpty ||
      completed.any((i) => i.sourceId == sourceId && i.seriesId == seriesId)) {
    return;
  }
  final path = p.join(docsDir, 'covers', sourceId, '$seriesId.jpg');
  try {
    File(path).deleteSync();
    evictCover(path);
  } catch (_) {
    // Already gone.
  }
}

/// What's on this device: finished downloads' comic ids, and how many per
/// series. Offline mode dims and filters by this.
final onDeviceProvider =
    Provider<({Set<String> comicIds, Map<String, int> perSeries})>((ref) {
  // Rebuild only when the set of finished downloads changes, not on every
  // progress tick of an active download.
  ref.watch(downloadStateProvider.select((s) => (s.value?.completed ?? const [])
      .where((i) => i.status == DownloadStatus.completed)
      .map((i) => '${i.sourceId}:${i.comicId}')
      .join(',')));
  // Comic ids can collide across servers: only the active one's count.
  final sourceId = ref.watch(activeSourceIdProvider);
  final items = ref.read(downloadStateProvider).value?.completed ??
      const <DownloadItem>[];
  final comicIds = <String>{};
  final perSeries = <String, int>{};
  for (final i in items) {
    if (i.status != DownloadStatus.completed || i.sourceId != sourceId) {
      continue;
    }
    comicIds.add(i.comicId);
    perSeries.update(i.seriesId, (n) => n + 1, ifAbsent: () => 1);
  }
  return (comicIds: comicIds, perSeries: perSeries);
});

/// Stream of download state updates.
final downloadStateProvider = StreamProvider<DownloadManagerState>((ref) {
  final manager = ref.watch(downloadManagerProvider);
  if (manager == null) return const Stream.empty();
  return manager.stateStream;
});

/// Get the local pages directory path for a completely downloaded comic.
Future<String?> downloadedPagesPath(String sourceId, String comicId) async {
  final docsDir = await getApplicationDocumentsDirectory();
  final comicDir = p.join(docsDir.path, 'downloads', sourceId, comicId);
  return isDownloadComplete(comicDir) ? p.join(comicDir, 'pages') : null;
}

/// Get total storage used by downloads.
Future<int> downloadedStorageBytes() async {
  final docsDir = await getApplicationDocumentsDirectory();
  final downloadsDir = Directory(p.join(docsDir.path, 'downloads'));
  if (!downloadsDir.existsSync()) return 0;

  int total = 0;
  await for (final entity in downloadsDir.list(recursive: true)) {
    if (entity is File) {
      total += await entity.length();
    }
  }
  return total;
}

/// Returns every comic id under `downloads/<sourceId>/` whose download is
/// complete ([isDownloadComplete]). Family key is just the sourceId (a String) so the cache is
/// stable across rebuilds — callers intersect with whatever series they care
/// about. Watches [downloadStateProvider] so it refreshes whenever a download
/// finishes or is deleted.
final downloadedComicIdsProvider =
    FutureProvider.family<Set<String>, String>((ref, sourceId) async {
  // Re-evaluate whenever the download manager state changes.
  ref.watch(downloadStateProvider);
  final docsDir = await ref.watch(docsDirProvider.future);
  final sourceDir = Directory('$docsDir/downloads/$sourceId');
  if (!await sourceDir.exists()) return const <String>{};
  final downloaded = <String>{};
  await for (final entity in sourceDir.list()) {
    if (entity is! Directory) continue;
    if (isDownloadComplete(entity.path)) downloaded.add(p.basename(entity.path));
  }
  return downloaded;
});

/// "Delete issues when I finish them": the reader removes a download once
/// you reach its last page. Shared by Settings and the Downloads page.
final autoCleanupDownloadsProvider =
    NotifierProvider<AutoCleanupNotifier, bool>(AutoCleanupNotifier.new);

class AutoCleanupNotifier extends Notifier<bool> {
  static const _key = 'auto_cleanup_downloads';

  @override
  bool build() => ref.watch(sharedPrefsProvider).getBool(_key) ?? false;

  Future<void> set(bool on) async {
    state = on;
    await ref.read(sharedPrefsProvider).setBool(_key, on);
  }
}

/// Scan downloaded comics and return them as Series for offline library display.
final downloadedLibraryProvider =
    FutureProvider.autoDispose<List<Series>>((ref) async {
  ref.watch(downloadStateProvider);
  final docsDir = await getApplicationDocumentsDirectory();
  final downloadsDir = Directory(p.join(docsDir.path, 'downloads'));
  if (!downloadsDir.existsSync()) return [];

  final seriesMap = <String, List<Map<String, dynamic>>>{};

  await for (final sourceDir in downloadsDir.list()) {
    if (sourceDir is! Directory) continue;
    await for (final comicDir in sourceDir.list()) {
      if (comicDir is! Directory) continue;
      final metaFile = File(p.join(comicDir.path, 'metadata.json'));
      if (!metaFile.existsSync()) continue;
      final Map<String, dynamic> json;
      try {
        json = jsonDecode(await metaFile.readAsString()) as Map<String, dynamic>;
      } catch (_) {
        continue; // one bad file shouldn't blank the whole offline library
      }
      final seriesId = json['series_id'] as String? ?? '';
      seriesMap.putIfAbsent(seriesId, () => []).add(json);
    }
  }

  return seriesMap.entries.map((e) {
    final first = e.value.first;
    return Series(
      id: first['series_id'] as String? ?? '',
      name: first['series_name'] as String? ?? 'Unknown',
      folderPath: '',
      issueCount: e.value.length,
      readCount: 0,
      coverUrl: '',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }).toList();
});
