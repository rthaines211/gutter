import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/api_client.dart';
import '../services/mirror/mirror_database.dart';
import '../services/sync_queue.dart';
import 'cache_providers.dart';
import 'mirror_provider.dart';
import 'providers.dart';

/// Plain DI'd class — testable without Riverpod.
class MetadataEditor {
  MetadataEditor({
    required this.db,
    required this.client,
    required this.queue,
  });

  final MirrorDatabase db;
  final ApiClient client;
  final SyncQueue queue;

  /// Local-first: mirror write first, then PATCH server; enqueue on any error.
  Future<void> saveIssue(String comicId, Map<String, dynamic> fields) async {
    await db.updateIssuePayloadLocal(comicId, fields);
    try {
      await client.patchComicMetadata(comicId, fields);
    } catch (_) {
      await queue.enqueue({
        'type': 'comic_metadata',
        'payload': {'comic_id': comicId, 'fields': Map<String, dynamic>.from(fields)},
      });
    }
  }

  Future<void> saveSeries(String seriesId, Map<String, dynamic> fields) async {
    await db.updateSeriesPayloadLocal(seriesId, fields);
    try {
      await client.patchSeriesMetadata(seriesId, fields);
    } catch (_) {
      await queue.enqueue({
        'type': 'series_metadata',
        'payload': {'series_id': seriesId, 'fields': Map<String, dynamic>.from(fields)},
      });
    }
  }
}

/// Provider wiring the three deps.
/// syncQueueProvider returns SyncQueue? — we require it non-null here;
/// if it's null the queue falls back to a no-op (app is offline-only mode).
final metadataEditorProvider = Provider<MetadataEditor>((ref) {
  final queue = ref.watch(syncQueueProvider);
  // If there is no persistent queue path (docsDir hasn't resolved yet, or
  // tests/offline config), we still need a SyncQueue. Fall back to a temp-dir
  // path. NOTE: entries written to this fallback queue are NOT drained by
  // SyncQueueDrainer — they live only for the duration of the process. This
  // is accepted for the single-user case; the window is narrow (app startup).
  final effectiveQueue = queue ??
      SyncQueue(
        queuePath:
            '${Directory.systemTemp.path}/comic_reader_fallback_queue.json',
      );
  return MetadataEditor(
    db: ref.watch(mirrorDbProvider),
    client: ref.watch(apiClientProvider),
    queue: effectiveQueue,
  );
});
