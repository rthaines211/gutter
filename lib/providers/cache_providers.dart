import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/local_session_store.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../services/cache_layer.dart';
import '../services/sync_queue.dart';
import '../services/cached_api.dart';
import 'providers.dart';
import 'source_provider.dart';

final docsDirProvider = FutureProvider<String>((ref) async {
  final dir = await getApplicationDocumentsDirectory();
  return dir.path;
});

final cacheLayerProvider = Provider<CacheLayer?>((ref) {
  final docsDir = ref.watch(docsDirProvider).value;
  if (docsDir == null) return null;
  final source = ref.watch(activeSourceProvider);
  return CacheLayer(cacheDir: p.join(docsDir, 'cache', source.id));
});

final syncQueueProvider = Provider<SyncQueue?>((ref) {
  final docsDir = ref.watch(docsDirProvider).value;
  if (docsDir == null) return null;
  final source = ref.watch(activeSourceProvider);
  return SyncQueue(
      queuePath: p.join(docsDir, 'cache', source.id, 'sync_queue.json'));
});

/// The active source's on-device reading sessions (used by Komga sources).
final localSessionStoreProvider = Provider<LocalSessionStore?>((ref) {
  final docsDir = ref.watch(docsDirProvider).value;
  if (docsDir == null) return null;
  final source = ref.watch(activeSourceProvider);
  return LocalSessionStore(p.join(docsDir, 'cache', source.id, 'sessions.json'));
});

final cachedApiProvider = Provider<CachedApi?>((ref) {
  final client = ref.watch(apiClientProvider);
  final cache = ref.watch(cacheLayerProvider);
  if (cache == null) return null;
  return CachedApi(client: client, cache: cache);
});
