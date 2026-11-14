// lib/screens/downloads_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../config/comic_style.dart';
import '../config/source_urls.dart';
import '../config/string_utils.dart';
import '../config/app_theme.dart';
import '../config/scheme.dart';
import '../models/download_item.dart';
import '../models/series.dart';
import '../providers/accent_provider.dart';
import '../providers/cache_providers.dart';
import '../providers/connectivity_provider.dart';
import '../providers/download_provider.dart';
import '../providers/library_provider.dart';
import '../providers/providers.dart';
import '../providers/source_provider.dart';
import '../services/download_manager.dart';
import '../widgets/cover_flight_route.dart';
import '../widgets/pro_sheet.dart';
import 'reader_screen.dart';
import '../config/layout_breakpoint.dart';

/// What's on this device, as a split like the Library: storage and active
/// downloads on top, one row per series, and the selected series' issues in a
/// panel on the right (a pushed page on a phone).
class DownloadsScreen extends ConsumerStatefulWidget {
  const DownloadsScreen({super.key});

  @override
  ConsumerState<DownloadsScreen> createState() => _DownloadsScreenState();
}

/// Finished downloads grouped by series, newest download's series first.
Map<String, List<DownloadItem>> _bySeries(DownloadManagerState state) {
  final done = state.completed
      .where((i) => i.status == DownloadStatus.completed)
      .toList()
    ..sort((a, b) => b.addedAt.compareTo(a.addedAt));
  final out = <String, List<DownloadItem>>{};
  for (final i in done) {
    out.putIfAbsent(i.seriesId, () => []).add(i);
  }
  return out;
}

class _DownloadsScreenState extends ConsumerState<DownloadsScreen> {
  Color get accent => ref.watch(accentProvider).value ?? AppTheme.accent;

  int _storageBytes = 0;
  int? _freeBytes;
  int _seenCompleted = -1;
  String? _selected;

  Future<void> _loadStorage() async {
    int bytes;
    try {
      bytes = await downloadedStorageBytes();
    } catch (_) {
      return; // No documents directory (tests): keep the last figure.
    }
    final free = await deviceFreeBytes();
    if (mounted) {
      setState(() {
        _storageBytes = bytes;
        _freeBytes = free;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state =
        ref.watch(downloadStateProvider).value ?? const DownloadManagerState();
    final failed = state.completed
        .where((i) => i.status == DownloadStatus.failed)
        .toList();
    final bySeries = _bySeries(state);
    final count = bySeries.values.fold<int>(0, (n, l) => n + l.length);
    // Storage changes only when a download finishes or is removed.
    if (count != _seenCompleted) {
      _seenCompleted = count;
      _loadStorage();
    }

    final tablet = LayoutBreakpoint.isTablet(context);
    // The panel always shows a series on a tablet: the tapped one while it
    // has downloads, else the first.
    final selected = bySeries.containsKey(_selected)
        ? _selected
        : (tablet ? bySeries.keys.firstOrNull : null);

    final list = CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      slivers: [
        SliverToBoxAdapter(child: _header(context)),
        if (state.all.isNotEmpty)
          SliverToBoxAdapter(
              child: _summary(context, count, bySeries.length)),
        if (state.queue.isNotEmpty)
          SliverToBoxAdapter(child: _activeCard(context, state.queue)),
        if (failed.isNotEmpty) ...[
          _label(context, 'FAILED', trailing: _textButton(
              'Clear', context.scheme.t3,
              () => ref.read(downloadManagerProvider)?.clearFailed())),
          SliverList.list(
            children: [for (final i in failed) _failedRow(context, i)],
          ),
        ],
        if (bySeries.isNotEmpty) _label(context, 'SERIES'),
        SliverList.list(children: [
          for (final e in bySeries.entries)
            _SeriesRow(
              seriesId: e.key,
              items: e.value,
              accent: accent,
              selected: tablet && e.key == selected,
              onTap: () {
                HapticFeedback.selectionClick();
                if (tablet) {
                  setState(() => _selected = e.key);
                } else {
                  Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => _SeriesPage(seriesId: e.key),
                  ));
                }
              },
            ),
        ]),
        if (state.all.isNotEmpty)
          SliverToBoxAdapter(child: _autoDeleteRow(context)),
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
    );

    return Scaffold(
      backgroundColor: context.scheme.bg,
      body: SafeArea(
        child: !tablet || selected == null
            ? list
            : LayoutBuilder(
                builder: (context, box) {
                  final panelWidth =
                      box.maxWidth * LayoutBreakpoint.splitPanelFraction(context);
                  return Row(
                    children: [
                      Expanded(child: list),
                      Container(
                        width: panelWidth,
                        decoration: BoxDecoration(
                          color: context.scheme.bgRaised,
                          border: Border(
                            left: BorderSide(
                                color: context.scheme.hair, width: 1),
                          ),
                        ),
                        child: _SeriesPane(
                          key: ValueKey(selected),
                          seriesId: selected,
                        ),
                      ),
                    ],
                  );
                },
              ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Row(
        children: [
          // A rail tab has nothing to go back to.
          if (Navigator.canPop(context))
            IconButton(
              tooltip: 'Back',
              onPressed: () => Navigator.pop(context),
              padding: EdgeInsets.zero,
              alignment: Alignment.centerLeft,
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              icon: Icon(Icons.arrow_back_ios_rounded,
                  size: 20, color: context.scheme.t2),
            ),
          const Expanded(
            child: Text('Downloads', style: AppTheme.titleLarge),
          ),
        ],
      ),
    );
  }

  /// A ring of downloads against free space, with the totals beside it.
  Widget _summary(BuildContext context, int issues, int series) {
    final free = _freeBytes;
    final fraction = free == null || _storageBytes + free == 0
        ? 0.0
        : _storageBytes / (_storageBytes + free);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
      child: Row(
        children: [
          SizedBox(
            width: 46,
            height: 46,
            child: CircularProgressIndicator(
              // A sliver of colour even when downloads are tiny next to the
              // free space, so the ring reads as "some".
              value: _storageBytes == 0 ? 0 : fraction.clamp(0.03, 1.0),
              strokeWidth: 6,
              color: accent,
              backgroundColor: context.scheme.s2,
              strokeCap: StrokeCap.round,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    '${_formatBytes(_storageBytes)} on this '
                    '${LayoutBreakpoint.deviceNoun}',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: context.scheme.tx)),
                Text(
                    '$issues ${issues == 1 ? 'issue' : 'issues'} in $series series'
                    '${free == null ? '' : ' · ${_formatBytes(free)} free'}',
                    style: TextStyle(fontSize: 13, color: context.scheme.t2)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _autoDeleteRow(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 4),
      child: Container(
        padding: const EdgeInsets.only(top: 12),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: context.scheme.hair)),
        ),
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
      ),
    );
  }

  Widget _label(BuildContext context, String text, {Widget? trailing}) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 6),
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
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
        decoration: BoxDecoration(
          color: context.scheme.s1,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(children: [
                      TextSpan(
                          text: stripComicExtension(item.comicName),
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: context.scheme.tx)),
                      if (waiting > 0)
                        TextSpan(
                            text: ' · $waiting more waiting',
                            style: TextStyle(
                                fontSize: 12, color: context.scheme.t3)),
                    ]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14),
                  ),
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
                  Text(stripComicExtension(item.comicName),
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

/// [items] in series order, so a list reads #1, #2, #3.
List<DownloadItem> _inSeriesOrder(
    List<DownloadItem> items, SeriesDetail? detail) {
  final order = {
    for (final (n, i) in (detail?.issues ?? <SeriesIssue>[]).indexed) i.id: n
  };
  return [...items]
    ..sort((a, b) => (order[a.comicId] ?? 1 << 30)
        .compareTo(order[b.comicId] ?? 1 << 30));
}

/// First page file of a downloaded comic, for thumbnails (works offline,
/// unlike covers).
final _thumbs = <String, File?>{};
File? _firstPage(String? docsDir, DownloadItem item) {
  if (docsDir == null) return null;
  final pagesDir =
      p.join(docsDir, 'downloads', item.sourceId, item.comicId, 'pages');
  return _thumbs.putIfAbsent(pagesDir, () {
    try {
      final files = Directory(pagesDir).listSync().whereType<File>().toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      return files.firstOrNull;
    } catch (_) {
      return null;
    }
  });
}

class _Thumb extends StatelessWidget {
  final File? file;
  final double width;
  final double border;

  const _Thumb(this.file, {required this.width, this.border = 1.5});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: width * 1.5,
      decoration: BoxDecoration(
        border: Border.all(color: context.scheme.ink, width: border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: file == null
            ? ColoredBox(color: context.scheme.s2)
            : Image.file(file!,
                fit: BoxFit.cover,
                cacheWidth: (width * 3).round(),
                errorBuilder: (_, _, _) =>
                    ColoredBox(color: context.scheme.s2)),
      ),
    );
  }
}

/// One series in the list: cover, size, and a dot per downloaded issue
/// (green read, accent reading, grey unread).
class _SeriesRow extends ConsumerWidget {
  final String seriesId;
  final List<DownloadItem> items;
  final Color accent;
  final bool selected;
  final VoidCallback onTap;

  const _SeriesRow({
    required this.seriesId,
    required this.items,
    required this.accent,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(seriesDetailProvider(seriesId)).value;
    final docsDir = ref.watch(docsDirProvider).value;
    final status = {
      for (final i in detail?.issues ?? <SeriesIssue>[]) i.id: i.status
    };
    final sorted = _inSeriesOrder(items, detail);
    final size = items.fold<int>(0, (s, i) => s + i.totalBytes);
    final name = detail?.name ?? items.first.seriesName;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
      child: Material(
        color: selected ? accent.withValues(alpha: 0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                _Thumb(_firstPage(docsDir, sorted.first), width: 48, border: 2),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: context.scheme.tx)),
                      const SizedBox(height: 2),
                      Text(
                          '${items.length} ${items.length == 1 ? 'issue' : 'issues'}'
                          ' · ${_formatBytes(size)}',
                          style: TextStyle(
                              fontSize: 13, color: context.scheme.t3)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          for (final i in sorted)
                            Container(
                              width: 9,
                              height: 9,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: switch (status[i.comicId]) {
                                  'completed' => AppTheme.green,
                                  'in_progress' => accent,
                                  _ => context.scheme.s3,
                                },
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: context.scheme.t3),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A phone has no room for the panel: the series opens as its own page.
class _SeriesPage extends StatelessWidget {
  final String seriesId;
  const _SeriesPage({required this.seriesId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.scheme.bg,
      body: SafeArea(child: _SeriesPane(seriesId: seriesId, showBack: true)),
    );
  }
}

/// The selected series: header with actions, then its downloaded issues
/// (tap to read, swipe to remove). Read state comes from the local mirror,
/// so this works offline.
class _SeriesPane extends ConsumerWidget {
  final String seriesId;
  final bool showBack;

  const _SeriesPane({super.key, required this.seriesId, this.showBack = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = ref.watch(accentProvider).value ?? AppTheme.accent;
    final state =
        ref.watch(downloadStateProvider).value ?? const DownloadManagerState();
    final items = _bySeries(state)[seriesId] ?? const <DownloadItem>[];
    if (items.isEmpty) {
      // Everything was removed: a pushed page has nothing left to show.
      if (showBack) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) Navigator.of(context).maybePop();
        });
      }
      return const SizedBox.shrink();
    }
    final detail = ref.watch(seriesDetailProvider(seriesId)).value;
    final docsDir = ref.watch(docsDirProvider).value;
    final comic = ComicTokens.watch(ref, context, accent);
    final issues = {for (final i in detail?.issues ?? <SeriesIssue>[]) i.id: i};
    final sorted = _inSeriesOrder(items, detail);
    final size = items.fold<int>(0, (s, i) => s + i.totalBytes);
    final name = detail?.name ?? items.first.seriesName;
    final read =
        items.where((i) => issues[i.comicId]?.status == 'completed').toList();
    final next = _nextToGet(ref, detail, state);
    final total = detail?.issues.length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
      children: [
        if (showBack)
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              tooltip: 'Back',
              onPressed: () => Navigator.pop(context),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              icon: Icon(Icons.arrow_back_ios_rounded,
                  size: 20, color: context.scheme.t2),
            ),
          ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Thumb(_firstPage(docsDir, sorted.first), width: 88, border: 2.5),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.displayTextStyle(comic, fontSize: 26)
                          .copyWith(color: context.scheme.tx, height: 1.05)),
                  const SizedBox(height: 4),
                  Text(
                      total != null && total > items.length
                          ? '${items.length} of $total issues downloaded · ${_formatBytes(size)}'
                          : '${items.length} ${items.length == 1 ? 'issue' : 'issues'} · ${_formatBytes(size)}',
                      style:
                          TextStyle(fontSize: 13, color: context.scheme.t3)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (next.isNotEmpty)
                        _Pill(
                          label: 'Get next ${next.length}',
                          color: accent,
                          onTap: () => _getNext(context, ref, detail!, next),
                        ),
                      if (read.isNotEmpty && read.length < items.length)
                        _Pill(
                          label: 'Remove read',
                          color: Colors.red[400]!,
                          onTap: () => _confirmRemove(context, ref, read,
                              title: 'Remove read issues?'),
                        ),
                      _Pill(
                        label: 'Remove all',
                        color: Colors.red[400]!,
                        onTap: () => _confirmRemove(context, ref, items,
                            title: 'Remove $name?'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
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
            onDismissed: (_) => _remove(ref, [item]),
            child: _IssueRow(
              item: item,
              issue: issues[item.comicId],
              thumb: _firstPage(docsDir, item),
              accent: accent,
              onTap: () => _open(context, item, detail),
            ),
          ),
      ],
    );
  }

  /// Up to three issues to download next: the first ones in series order
  /// that aren't finished and aren't on the device or in the queue. None for
  /// the local source (nothing to fetch), offline, or another server's series.
  List<SeriesIssue> _nextToGet(
      WidgetRef ref, SeriesDetail? detail, DownloadManagerState state) {
    if (detail == null ||
        ref.watch(isLocalSourceProvider) ||
        !ref.watch(connectivityProvider)) {
      return const [];
    }
    final sourceId = ref.watch(activeSourceProvider).id;
    final known = {
      for (final i in state.all)
        if (i.sourceId == sourceId && i.status != DownloadStatus.failed)
          i.comicId
    };
    return detail.issues
        .where((i) => i.status != 'completed' && !known.contains(i.id))
        .take(3)
        .toList();
  }

  void _getNext(BuildContext context, WidgetRef ref, SeriesDetail detail,
      List<SeriesIssue> next) {
    if (!requirePro(context, ref, reason: 'Downloads are part of Pro.')) return;
    final manager = ref.read(downloadManagerProvider);
    if (manager == null) return;
    HapticFeedback.mediumImpact();
    final source = ref.read(activeSourceProvider);
    // No auth here: the journal never stores credentials (DownloadManager
    // adds them at fetch time).
    final headers = {
      'Content-Type': 'application/json',
      'X-Device-ID': ref.read(serverConfigProvider).deviceId,
    };
    for (final issue in next) {
      manager.enqueue(
        comicId: issue.id,
        sourceId: source.id,
        seriesId: detail.id,
        seriesName: detail.name,
        comicName: issue.name,
        comicUrl: source.comicDownload(issue.id),
        headers: headers,
      );
    }
  }

  Future<void> _remove(WidgetRef ref, List<DownloadItem> items) async {
    final manager = ref.read(downloadManagerProvider);
    for (final i in items) {
      await manager?.delete(i.comicId, i.sourceId);
    }
  }

  Future<void> _confirmRemove(
      BuildContext context, WidgetRef ref, List<DownloadItem> items,
      {required String title}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(
            'Deletes ${items.length} downloaded ${items.length == 1 ? 'issue' : 'issues'} '
            'from this ${LayoutBreakpoint.deviceNoun}. Your reading progress stays.'),
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
      await _remove(ref, items);
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

class _Pill extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _Pill({required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.scheme.s1,
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        borderRadius: BorderRadius.circular(99),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(label,
              style: TextStyle(
                  color: color, fontSize: 13, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}

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
      trailing =
          const Icon(Icons.check_rounded, size: 18, color: AppTheme.green);
    } else if (status == 'in_progress' && page != null && total != null) {
      meta = 'Page ${page + 1} of $total';
      trailing = Text('Resume',
          style: TextStyle(
              fontSize: 13, color: accent, fontWeight: FontWeight.w600));
    } else {
      meta = 'Unread';
    }

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: context.scheme.hair)),
        ),
        child: Row(
          children: [
            _Thumb(thumb, width: 36),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(stripComicExtension(item.comicName),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: context.scheme.tx)),
                  const SizedBox(height: 2),
                  Text('$meta · ${_formatBytes(item.totalBytes)}',
                      style: TextStyle(
                          fontSize: 12,
                          color: status == 'in_progress'
                              ? accent
                              : context.scheme.t3)),
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
