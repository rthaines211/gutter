// lib/screens/downloads_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../config/app_theme.dart';
import '../config/scheme.dart';
import '../models/download_item.dart';
import '../models/series.dart';
import '../providers/accent_provider.dart';
import '../providers/cache_providers.dart';
import '../providers/download_provider.dart';
import '../providers/library_provider.dart';
import '../services/download_manager.dart';
import '../widgets/cover_flight_route.dart';
import 'reader_screen.dart';

/// What's on this iPad: active downloads on top, then one section per series
/// with tappable issue rows (read offline), per-issue swipe and per-series
/// "Remove all" to free space.
class DownloadsScreen extends ConsumerStatefulWidget {
  const DownloadsScreen({super.key});

  @override
  ConsumerState<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends ConsumerState<DownloadsScreen> {
  Color get accent => ref.watch(accentProvider).value ?? AppTheme.accent;

  int _storageBytes = 0;
  int _seenCompleted = -1;

  Future<void> _loadStorage() async {
    final bytes = await downloadedStorageBytes();
    if (mounted) setState(() => _storageBytes = bytes);
  }

  Future<void> _remove(List<DownloadItem> items) async {
    final manager = ref.read(downloadManagerProvider);
    for (final i in items) {
      await manager?.delete(i.comicId, i.sourceId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state =
        ref.watch(downloadStateProvider).value ?? const DownloadManagerState();
    final done = state.completed
        .where((i) => i.status == DownloadStatus.completed)
        .toList()
      ..sort((a, b) => b.addedAt.compareTo(a.addedAt));
    final failed = state.completed
        .where((i) => i.status == DownloadStatus.failed)
        .toList();
    // Storage changes only when a download finishes or is removed.
    if (done.length != _seenCompleted) {
      _seenCompleted = done.length;
      _loadStorage();
    }

    // Sections in order of the newest download in each series.
    final bySeries = <String, List<DownloadItem>>{};
    for (final i in done) {
      bySeries.putIfAbsent(i.seriesId, () => []).add(i);
    }

    return Scaffold(
      backgroundColor: context.scheme.bg,
      body: SafeArea(
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            SliverToBoxAdapter(child: _header(context)),
            SliverToBoxAdapter(child: _autoDeleteRow(context)),
            if (state.queue.isNotEmpty) ...[
              _label(context, 'DOWNLOADING · ${state.queue.length}'),
              SliverToBoxAdapter(child: _activeCard(context, state.queue)),
            ],
            if (failed.isNotEmpty) ...[
              _label(context, 'FAILED', trailing: _textButton(
                  'Clear', context.scheme.t3,
                  () => ref.read(downloadManagerProvider)?.clearFailed())),
              SliverList.list(
                children: [for (final i in failed) _failedRow(context, i)],
              ),
            ],
            for (final e in bySeries.entries)
              SliverToBoxAdapter(
                child: _SeriesSection(
                  seriesId: e.key,
                  items: e.value,
                  accent: accent,
                  onRemove: _remove,
                ),
              ),
            if (state.all.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Text(
                    'No downloads yet.\nDownload comics from a series page.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: context.scheme.t2),
                  ),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 40)),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Row(
        children: [
          // A rail tab has nothing to go back to.
          if (Navigator.canPop(context))
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Icon(Icons.arrow_back_ios_rounded,
                    size: 20, color: context.scheme.t2),
              ),
            ),
          const Expanded(
            child: Text('Downloads', style: AppTheme.titleLarge),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: context.scheme.s1,
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              '${_formatBytes(_storageBytes)} used',
              style: TextStyle(color: context.scheme.t2, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _autoDeleteRow(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Delete issues when I finish them',
                    style: TextStyle(fontSize: 14, color: context.scheme.tx)),
                Text('Frees space as you read; progress is kept',
                    style: TextStyle(fontSize: 12, color: context.scheme.t3)),
              ],
            ),
          ),
          Switch.adaptive(
            value: ref.watch(autoCleanupDownloadsProvider),
            activeTrackColor: accent,
            onChanged: (v) =>
                ref.read(autoCleanupDownloadsProvider.notifier).set(v),
          ),
        ],
      ),
    );
  }

  Widget _label(BuildContext context, String text, {Widget? trailing}) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        child: Row(
          children: [
            Expanded(
              child: Text(text,
                  style: TextStyle(
                    color: context.scheme.t3,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  )),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }

  Widget _textButton(String text, Color color, VoidCallback onTap) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(text,
            style: TextStyle(
                color: color, fontSize: 13, fontWeight: FontWeight.w600)),
      ),
    );
  }

  /// The comic downloading now, with progress and cancel; the rest are a count.
  Widget _activeCard(BuildContext context, List<DownloadItem> queue) {
    final item = queue.first;
    final manager = ref.read(downloadManagerProvider);
    final waiting = queue.length - 1;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
        decoration: BoxDecoration(
          color: context.scheme.s1,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.comicName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: context.scheme.tx)),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: item.status == DownloadStatus.queued
                          ? null
                          : item.progress,
                      minHeight: 5,
                      color: accent,
                      backgroundColor: context.scheme.s2,
                    ),
                  ),
                  if (waiting > 0) ...[
                    const SizedBox(height: 6),
                    Text('$waiting more queued',
                        style:
                            TextStyle(fontSize: 12, color: context.scheme.t3)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text('${(item.progress * 100).toInt()}%',
                style: TextStyle(
                    fontSize: 12,
                    color: accent,
                    fontFamily: '.SF Mono',
                    fontWeight: FontWeight.w600)),
            IconButton(
              tooltip: 'Cancel',
              icon: Icon(Icons.close_rounded,
                  size: 18, color: context.scheme.t3),
              onPressed: () => manager?.cancel(item.comicId, item.sourceId),
            ),
            if (waiting > 0)
              IconButton(
                tooltip: 'Cancel all',
                icon: Icon(Icons.clear_all_rounded,
                    size: 20, color: context.scheme.t3),
                onPressed: () {
                  for (final i in queue.reversed) {
                    manager?.cancel(i.comicId, i.sourceId);
                  }
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _failedRow(BuildContext context, DownloadItem item) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        decoration: BoxDecoration(
          color: context.scheme.s1,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline_rounded, size: 18, color: Colors.red[400]),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.comicName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: context.scheme.tx)),
                  if (item.error != null)
                    Text(item.error!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style:
                            TextStyle(fontSize: 12, color: Colors.red[400])),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Retry',
              icon: Icon(Icons.refresh_rounded, size: 18, color: accent),
              onPressed: () => ref
                  .read(downloadManagerProvider)
                  ?.retry(item.comicId, item.sourceId),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatBytes(int bytes) {
  final mb = bytes / (1024 * 1024);
  return mb >= 1024
      ? '${(mb / 1024).toStringAsFixed(1)} GB'
      : '${mb.toStringAsFixed(0)} MB';
}

/// One series: header with size and "Remove all", then its downloaded issues.
/// Read state and the issue list for next/previous come from the local
/// mirror, so this works offline.
class _SeriesSection extends ConsumerWidget {
  final String seriesId;
  final List<DownloadItem> items;
  final Color accent;
  final Future<void> Function(List<DownloadItem>) onRemove;

  const _SeriesSection({
    required this.seriesId,
    required this.items,
    required this.accent,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(seriesDetailProvider(seriesId)).value;
    final docsDir = ref.watch(docsDirProvider).value;
    final issues = {for (final i in detail?.issues ?? <SeriesIssue>[]) i.id: i};
    // Series order, so a section reads #1, #2, #3.
    final order = {
      for (final (n, i) in (detail?.issues ?? <SeriesIssue>[]).indexed) i.id: n
    };
    final sorted = [...items]
      ..sort((a, b) => (order[a.comicId] ?? 1 << 30)
          .compareTo(order[b.comicId] ?? 1 << 30));
    final size = items.fold<int>(0, (s, i) => s + i.totalBytes);
    final name = detail?.name ?? items.first.seriesName;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${name.toUpperCase()} · ${items.length} '
                  '${items.length == 1 ? 'ISSUE' : 'ISSUES'} · ${_formatBytes(size)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.scheme.t3,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _confirmRemoveAll(context, name),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Text('Remove all',
                      style: TextStyle(
                          color: Colors.red[400],
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
        for (final item in sorted)
          Dismissible(
            key: ValueKey('${item.sourceId}:${item.comicId}'),
            direction: DismissDirection.endToStart,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 24),
              color: Colors.red.withValues(alpha: 0.2),
              child: Icon(Icons.delete_outline, color: Colors.red[400]),
            ),
            onDismissed: (_) => onRemove([item]),
            child: _IssueRow(
              item: item,
              issue: issues[item.comicId],
              thumb: docsDir == null
                  ? null
                  : _firstPage(p.join(docsDir, 'downloads', item.sourceId,
                      item.comicId, 'pages')),
              accent: accent,
              onTap: () => _open(context, item, detail),
            ),
          ),
      ],
    );
  }

  Future<void> _confirmRemoveAll(BuildContext context, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove $name?'),
        content: Text(
            'Deletes ${items.length} downloaded ${items.length == 1 ? 'issue' : 'issues'} '
            'from this iPad. Your reading progress stays.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Remove', style: TextStyle(color: Colors.red[400]))),
        ],
      ),
    );
    if (ok == true) {
      HapticFeedback.mediumImpact();
      await onRemove(items);
    }
  }

  void _open(BuildContext context, DownloadItem item, SeriesDetail? detail) {
    HapticFeedback.selectionClick();
    final issue = detail?.issues.where((i) => i.id == item.comicId).firstOrNull;
    final page = issue?.currentPage ?? 0;
    final total = issue?.totalPages ?? 0;
    final index = detail?.issues.indexWhere((i) => i.id == item.comicId) ?? -1;
    Navigator.of(context).push(readerRoute<void>(
      context,
      comicId: item.comicId,
      builder: (_) => ReaderScreen(
        comicId: item.comicId,
        comicPath: issue?.name ?? item.comicName,
        // A finished book reopens at the start; its saved page is one past
        // the last image.
        initialPage: total > 0 && page >= total ? 0 : page,
        seriesIssues: index >= 0 ? detail!.issues : null,
        currentIssueIndex: index >= 0 ? index : null,
        seriesId: item.seriesId.isEmpty ? null : item.seriesId,
        seriesName: detail?.name ?? item.seriesName,
      ),
    ));
  }
}

/// First page file, for the row thumbnail (works offline, unlike covers).
final _thumbs = <String, File?>{};
File? _firstPage(String pagesDir) => _thumbs.putIfAbsent(pagesDir, () {
      try {
        final files = Directory(pagesDir).listSync().whereType<File>().toList()
          ..sort((a, b) => a.path.compareTo(b.path));
        return files.firstOrNull;
      } catch (_) {
        return null;
      }
    });

class _IssueRow extends StatelessWidget {
  final DownloadItem item;
  final SeriesIssue? issue;
  final File? thumb;
  final Color accent;
  final VoidCallback onTap;

  const _IssueRow({
    required this.item,
    required this.issue,
    required this.thumb,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final status = issue?.status;
    final page = issue?.currentPage;
    final total = issue?.totalPages;
    final String meta;
    Widget? trailing;
    if (status == 'completed') {
      meta = 'Read';
      trailing = const Icon(Icons.check_rounded, size: 18, color: AppTheme.green);
    } else if (status == 'in_progress' && page != null && total != null) {
      meta = 'Page ${page + 1} of $total';
      trailing = Text('Reading',
          style: TextStyle(
              fontSize: 12, color: accent, fontWeight: FontWeight.w600));
    } else {
      meta = 'Unread';
    }

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: SizedBox(
                width: 32,
                height: 48,
                child: thumb == null
                    ? ColoredBox(color: context.scheme.s2)
                    : Image.file(thumb!,
                        fit: BoxFit.cover,
                        cacheWidth: 96,
                        errorBuilder: (_, _, _) =>
                            ColoredBox(color: context.scheme.s2)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.comicName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: context.scheme.tx)),
                  const SizedBox(height: 2),
                  Text(meta,
                      style:
                          TextStyle(fontSize: 12, color: context.scheme.t3)),
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}
