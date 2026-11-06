import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/comic_info.dart';
import '../models/bookmark.dart';
import '../models/chapter.dart';
import '../models/series.dart';
import '../services/download_manager.dart';
import '../services/api_client.dart';
import '../services/app_logger.dart';
import 'providers.dart';
import 'cache_providers.dart';
import 'connectivity_provider.dart';
import 'mirror_provider.dart';
import 'source_provider.dart';
import '../services/mirror/mirror_database.dart';
import '../services/sync_queue.dart';
import 'app_breadcrumbs.dart';

String _slugify(String name) {
  var s = name.trim().toLowerCase();
  s = s.replaceAll(RegExp(r'[^a-z0-9]+'), '-');
  s = s.replaceAll(RegExp(r'-{2,}'), '-');
  s = s.replaceAll(RegExp(r'^-|-$'), '');
  return s;
}

String? _seriesIdFromComicId(String comicId) {
  try {
    final padded = comicId.padRight((comicId.length + 3) ~/ 4 * 4, '=');
    final path = utf8.decode(base64Url.decode(padded));
    final dir = path.contains('/') ? path.substring(0, path.lastIndexOf('/')) : null;
    if (dir == null || dir.isEmpty) return null;
    return _slugify(dir);
  } catch (_) {
    return null;
  }
}

class ReaderState {
  final String comicId;
  final String comicPath;
  final ComicInfo? info;
  final int currentPage;
  final List<Bookmark> bookmarks;
  final List<Chapter> chapters;
  final List<SeriesIssue>? seriesIssues;
  final int? currentIssueIndex;
  final bool isOnLastPage;

  const ReaderState({
    required this.comicId,
    required this.comicPath,
    this.info,
    this.currentPage = 0,
    this.bookmarks = const [],
    this.chapters = const [],
    this.seriesIssues,
    this.currentIssueIndex,
    this.isOnLastPage = false,
  });

  SeriesIssue? get nextIssue {
    if (seriesIssues == null || currentIssueIndex == null) return null;
    final nextIdx = currentIssueIndex! + 1;
    if (nextIdx >= seriesIssues!.length) return null;
    return seriesIssues![nextIdx];
  }

  bool get hasSeriesContext =>
      seriesIssues != null && currentIssueIndex != null;

  ReaderState copyWith({
    String? comicId,
    String? comicPath,
    ComicInfo? info,
    int? currentPage,
    List<Bookmark>? bookmarks,
    List<Chapter>? chapters,
    List<SeriesIssue>? seriesIssues,
    int? currentIssueIndex,
    bool? isOnLastPage,
  }) {
    return ReaderState(
      comicId: comicId ?? this.comicId,
      comicPath: comicPath ?? this.comicPath,
      info: info ?? this.info,
      currentPage: currentPage ?? this.currentPage,
      bookmarks: bookmarks ?? this.bookmarks,
      chapters: chapters ?? this.chapters,
      seriesIssues: seriesIssues ?? this.seriesIssues,
      currentIssueIndex: currentIssueIndex ?? this.currentIssueIndex,
      isOnLastPage: isOnLastPage ?? this.isOnLastPage,
    );
  }
}

typedef ReaderKey = ({
  String comicId,
  String comicPath,
  List<SeriesIssue>? seriesIssues,
  int? currentIssueIndex,
});

class ReaderNotifier extends AsyncNotifier<ReaderState> {
  final String comicId;
  final String comicPath;
  final List<SeriesIssue>? seriesIssues;
  final int? currentIssueIndex;
  late ApiClient _client;
  SyncQueue? _syncQueue;
  // _saveProgress also runs from ref.onDispose, where ANY use of ref or state
  // throws in Riverpod 3. So everything it needs must already live in fields:
  // _mirrorDb/_syncQueue are captured at build, and _pendingSave snapshots the
  // progress values at schedule time — that snapshot is what makes the
  // dispose-flush actually save instead of silently throwing.
  late MirrorDatabase _mirrorDb;
  late AppBreadcrumbsNotifier _breadcrumbs;
  Timer? _saveTimer;
  ({String comicId, int currentPage, int totalPages})? _pendingSave;

  /// While set, progress saves write this page instead of the current one:
  /// an undoable jump isn't "where I'm reading" until the reader reads on.
  int? _heldPage;
  @visibleForTesting
  int? get heldPage => _heldPage;

  ReaderNotifier(
    this.comicId,
    this.comicPath, {
    this.seriesIssues,
    this.currentIssueIndex,
  });

  @override
  Future<ReaderState> build() async {
    _client = ref.watch(apiClientProvider);
    _syncQueue = ref.read(syncQueueProvider);
    _mirrorDb = ref.read(mirrorDbProvider);
    _breadcrumbs = ref.read(appBreadcrumbsProvider.notifier);
    // read, not watch: only the initial info fetch needs it, and a flip
    // mid-read rebuilt the notifier at page 0, then saved page 0 as progress.
    final isOnline = ref.read(connectivityProvider);

    ref.onDispose(() {
      // If a debounced save was pending, flush it so swipe-back doesn't drop
      // the last page turns. Fire-and-forget is acceptable here because the
      // Read tab refetch is gated on the explicit close handler awaiting.
      final hadPendingSave = _saveTimer?.isActive ?? false;
      _saveTimer?.cancel();
      if (hadPendingSave) {
        _saveProgress();
      }
      // Captured at build: ref.read inside onDispose asserts in Riverpod 3.
      try {
        _breadcrumbs.readerClosed();
      } catch (_) {
        // Whole-container teardown — breadcrumbs already disposed.
      }
    });

    ComicInfo? info;
    String? infoSource;
    if (isOnline) {
      try {
        info = await _client.getComicInfo(comicId)
            .timeout(const Duration(seconds: 5));
        infoSource = 'network';
      } catch (e) {
        AppLogger.instance.reader(
          level: LogLevel.warn,
          message: 'getComicInfo failed',
          context: {'comicId': comicId, 'error': e.toString()},
        );
      }
    }

    var resolvedIssues = seriesIssues;
    var resolvedIndex = currentIssueIndex;
    if (resolvedIssues == null && isOnline) {
      final seriesId = await _mirrorDb.seriesIdForComic(comicId) ??
          _seriesIdFromComicId(comicId);
      if (seriesId != null) {
        try {
          final detail = await _client.fetchSeriesDetail(seriesId)
              .timeout(const Duration(seconds: 5));
          resolvedIssues = detail.issues;
          resolvedIndex = detail.issues.indexWhere((i) => i.id == comicId);
          if (resolvedIndex < 0) resolvedIndex = null;
        } catch (e) {
          AppLogger.instance.reader(
            level: LogLevel.warn,
            message: 'fetchSeriesDetail failed',
            context: {'seriesId': seriesId, 'error': e.toString()},
          );
        }
      }
    }

    if (info == null) {
      final docsDir = ref.read(docsDirProvider).value;
      final sourceId = ref.read(activeSourceProvider).id;
      if (docsDir != null) {
        final comicDir = '$docsDir/downloads/$sourceId/$comicId';
        if (isDownloadComplete(comicDir)) {
          final pageCount =
              Directory('$comicDir/pages').listSync().whereType<File>().length;
          info = ComicInfo(title: comicPath, pageCount: pageCount);
          infoSource = 'local';
        }
      }
    }

    final pageCount = info?.pageCount ?? 0;
    AppLogger.instance.reader(
      level: pageCount == 0 ? LogLevel.warn : LogLevel.info,
      message: pageCount == 0 ? 'reader has no pages' : 'reader info loaded',
      context: {
        'comicId': comicId,
        'pageCount': pageCount,
        'source': infoSource ?? 'none',
        'online': isOnline,
      },
    );

    ref.read(appBreadcrumbsProvider.notifier).readerOpened(
      comicId: comicId,
      totalPages: pageCount,
      initialPage: 0,
    );

    final rawChapters = await _mirrorDb.chaptersForComic(comicId);
    final loadedChapters =
        rawChapters.map((m) => Chapter.fromJson(m)).toList();

    return ReaderState(
      comicId: comicId,
      comicPath: comicPath,
      info: info,
      chapters: loadedChapters,
      seriesIssues: resolvedIssues,
      currentIssueIndex: resolvedIndex,
    );
  }

  ReaderState get _current => state.value ??
      ReaderState(
        comicId: comicId,
        comicPath: comicPath,
        seriesIssues: seriesIssues,
        currentIssueIndex: currentIssueIndex,
      );

  void goToPage(int page) {
    final current = _current;
    if (current.info == null) return;
    final pageCount = current.info!.pageCount;
    // Allow landing on the virtual end-card index when there is series context.
    final maxIndex = current.hasSeriesContext ? pageCount : pageCount - 1;
    final clamped = page.clamp(0, maxIndex);
    // isOnLastPage stays true ONLY on the actual last image, so existing
    // scrubber/spread consumers see no behavior change.
    final onLastPage =
        clamped == pageCount - 1 && current.hasSeriesContext;
    state = AsyncData(
        current.copyWith(currentPage: clamped, isOnLastPage: onLastPage));
    ref.read(appBreadcrumbsProvider.notifier).readerPageTurn(
      comicId: current.comicId,
      page: clamped,
    );
    _scheduleSave();
  }

  /// Hold progress at [page] (null releases it). Reschedules the save so the
  /// pending snapshot — the one the dispose flush uses — matches.
  void holdProgressAt(int? page) {
    _heldPage = page;
    _scheduleSave();
  }

  /// Drop the hold without saving. [cancelPendingSave] also drops a queued
  /// save — completion needs that, or the dispose flush would rewrite a
  /// mid-issue page over the "completed" write.
  void releaseHold({bool cancelPendingSave = false}) {
    _heldPage = null;
    if (cancelPendingSave) {
      _saveTimer?.cancel();
      _pendingSave = null;
    }
  }

  void nextPage() => goToPage(_current.currentPage + 1);
  void prevPage() => goToPage(_current.currentPage - 1);

  void toggleBookmark(int pageNum, {String? note}) {
    final current = _current;
    final existing =
        current.bookmarks.where((b) => b.pageNum == pageNum).toList();
    final List<Bookmark> updated;
    if (existing.isNotEmpty) {
      updated = current.bookmarks.where((b) => b.pageNum != pageNum).toList();
    } else {
      updated = [
        ...current.bookmarks,
        Bookmark(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          comicId: current.comicId,
          pageNum: pageNum,
          note: note,
          createdAt: DateTime.now(),
        ),
      ];
    }
    state = AsyncData(current.copyWith(bookmarks: updated));
    _scheduleSave();
  }

  bool isBookmarked(int pageNum) =>
      _current.bookmarks.any((b) => b.pageNum == pageNum);

  void addChapter(int pageNum, String title) {
    final current = _current;
    final pageCount = current.info?.pageCount ?? 0;
    if (pageNum < 0 || (pageCount > 0 && pageNum >= pageCount)) return;
    final resolved = title.trim().isEmpty
        ? 'Chapter ${current.chapters.length + 1}'
        : title.trim();
    final next = current.chapters.where((c) => c.pageNum != pageNum).toList()
      ..add(Chapter.create(
          comicId: current.comicId, pageNum: pageNum, title: resolved));
    next.sort((a, b) => a.pageNum.compareTo(b.pageNum));
    state = AsyncData(current.copyWith(chapters: next));
    _persistChapters();
  }

  void renameChapter(String id, String title) {
    final current = _current;
    final t = title.trim();
    if (t.isEmpty) return;
    final next = current.chapters
        .map((c) => c.id == id ? c.copyWith(title: t) : c)
        .toList();
    state = AsyncData(current.copyWith(chapters: next));
    _persistChapters();
  }

  void deleteChapter(String id) {
    final current = _current;
    final next = current.chapters.where((c) => c.id != id).toList();
    state = AsyncData(current.copyWith(chapters: next));
    _persistChapters();
  }

  /// The page to persist. Without series context there is no end card, so
  /// reaching the last image is the only "finished" signal: save it as
  /// pageCount, which the server and mirror treat as read.
  int _progressPage(ReaderState current) {
    final held = _heldPage;
    if (held != null) return held;
    final pageCount = current.info!.pageCount;
    if (!current.hasSeriesContext && current.currentPage == pageCount - 1) {
      return pageCount;
    }
    return current.currentPage;
  }

  void _scheduleSave() {
    // Snapshot while the provider is still alive — _saveProgress may later run
    // from ref.onDispose, where reading state throws (Riverpod 3).
    final current = _current;
    if (current.info != null) {
      _pendingSave = (
        comicId: current.comicId,
        currentPage: _progressPage(current),
        totalPages: current.info!.pageCount,
      );
    }
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 2), _saveProgress);
  }

  Future<void> _saveProgress() async {
    // Prefer live state (includes bookmarks). Reading state throws if the
    // provider is disposed (the onDispose flush path) — fall back to the
    // snapshot captured in _scheduleSave, which has no bookmarks.
    String comicId;
    int currentPage;
    int totalPages;
    List<Bookmark>? bookmarks;
    try {
      final current = _current;
      if (current.info == null) return;
      comicId = current.comicId;
      currentPage = _progressPage(current);
      totalPages = current.info!.pageCount;
      bookmarks = current.bookmarks;
    } catch (_) {
      final pending = _pendingSave;
      if (pending == null) return;
      comicId = pending.comicId;
      currentPage = pending.currentPage;
      totalPages = pending.totalPages;
    }
    _pendingSave = null;
    // Progress only — chapters are NOT carried here. They persist separately via
    // _persistChapters() so a routine progress save can never wipe the chapter
    // set (mirror omits the column, server omits the field). Local-first: the
    // mirror is the UI's source of truth, so shelves update instantly even if
    // the network write fails.
    await _mirrorDb.saveProgressLocal(
      comicId: comicId,
      currentPage: currentPage,
      totalPages: totalPages,
    );
    // Auto-remove a series from queues once it's fully read.
    for (final q in await _mirrorDb.autoRemoveOnComplete(comicId)) {
      await _syncQueue?.enqueue({'type': 'queue_upsert', 'payload': q.toSyncJson()});
    }
    try {
      await _client.updateProgress(
        comicId: comicId,
        currentPage: currentPage,
        totalPages: totalPages,
        bookmarks: bookmarks,
      );
    } catch (_) {
      await _syncQueue?.enqueue({
        'type': 'progress',
        'payload': {
          'comic_id': comicId,
          'current_page': currentPage,
          'total_pages': totalPages,
        },
      });
    }
  }

  /// Persists the current chapter set (mirror + server) independently of
  /// progress saves. Called after every chapter mutation; both writes carry the
  /// full list, so the backend's replace-set stays correct without progress
  /// saves ever touching chapters.
  Future<void> _persistChapters() async {
    final ReaderState current;
    try {
      current = _current;
    } catch (_) {
      return; // provider disposed mid-op
    }
    if (current.info == null) return;
    final comicId = current.comicId;
    final currentPage = _progressPage(current);
    final totalPages = current.info!.pageCount;
    final chapters = current.chapters;
    final chaptersJson = chapters.map((c) => c.toJson()).toList();
    await _mirrorDb.saveProgressLocal(
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
        chapters: chapters,
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

  Future<void> saveProgressNow() => _saveProgress();
}

final readerProvider = AsyncNotifierProvider.family
    .autoDispose<ReaderNotifier, ReaderState, ReaderKey>(
  (arg) => ReaderNotifier(
    arg.comicId,
    arg.comicPath,
    seriesIssues: arg.seriesIssues,
    currentIssueIndex: arg.currentIssueIndex,
  ),
);
