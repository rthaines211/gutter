// lib/services/chapter_writer.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/chapter.dart';
import '../models/chapter_candidate.dart';
import '../providers/providers.dart';
import '../providers/mirror_provider.dart';
import '../providers/cache_providers.dart';
import 'api_client.dart';
import 'mirror/mirror_database.dart';
import 'sync_queue.dart';

/// Merges detected [candidates] into [existing] chapters: dedupe by page with
/// existing (user-authored) chapters winning, sorted by page.
List<Chapter> mergeDetectedChapters(
  String comicId,
  List<Chapter> existing,
  List<ChapterCandidate> candidates,
) {
  final byPage = <int, Chapter>{};
  for (final c in existing) {
    byPage[c.pageNum] = c;
  }
  for (final cand in candidates) {
    byPage.putIfAbsent(
      cand.page,
      () => Chapter.create(comicId: comicId, pageNum: cand.page, title: cand.title),
    );
  }
  final out = byPage.values.toList()..sort((a, b) => a.pageNum.compareTo(b.pageNum));
  return out;
}

/// Writes detected chapters for a comic by id — independent of any open reader.
/// Mirror-first, then PUT to the server (enqueue on failure), matching
/// ReaderNotifier._saveProgress.
class ChapterWriter {
  final MirrorDatabase _mirror;
  final ApiClient _client;
  final SyncQueue? _syncQueue;

  ChapterWriter(this._mirror, this._client, this._syncQueue);

  Future<void> addChapters(String comicId, List<ChapterCandidate> candidates) async {
    if (candidates.isEmpty) return;
    final existing = await _mirror.progressForComic(comicId);
    final currentPage = existing?.currentPage ?? 0;
    final totalPages = existing?.totalPages ?? 0;
    final existingChapters =
        (existing?.chapters ?? const []).map(Chapter.fromJson).toList();

    final merged = mergeDetectedChapters(comicId, existingChapters, candidates);
    final chaptersJson = merged.map((c) => c.toJson()).toList();

    await _mirror.saveProgressLocal(
      comicId: comicId,
      currentPage: currentPage,
      totalPages: totalPages,
      chapters: chaptersJson,
    );
    try {
      await _client.updateProgress(
        comicId: comicId,
        currentPage: currentPage,
        totalPages: totalPages,
        chapters: merged,
      );
    } catch (_) {
      await _syncQueue?.enqueue({
        'type': 'progress',
        'payload': {
          'comic_id': comicId,
          'current_page': currentPage,
          'total_pages': totalPages,
          'chapters': chaptersJson,
        },
      });
    }
  }
}

final chapterWriterProvider = Provider<ChapterWriter>((ref) => ChapterWriter(
      ref.read(mirrorDbProvider),
      ref.read(apiClientProvider),
      ref.read(syncQueueProvider),
    ));
