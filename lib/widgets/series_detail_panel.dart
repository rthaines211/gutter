// lib/widgets/series_detail_panel.dart
import 'dart:async';
import 'pro_sheet.dart';
import '../config/source_urls.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/app_theme.dart';
import '../config/layout_breakpoint.dart';
import '../config/scheme.dart';
import '../models/series.dart';
import '../providers/library_provider.dart';
import '../providers/providers.dart';
import '../providers/download_provider.dart';
import '../providers/source_provider.dart';
import '../providers/connectivity_provider.dart';
import '../providers/mirror_provider.dart';
import '../screens/reader_screen.dart';
import '../screens/series_detail_screen.dart';
import '../services/issue_gaps.dart';
import 'missing_issue_slot.dart';
import 'riffle_entry.dart';
import 'series_detail_header.dart';
import 'series_download_sheet.dart';
import 'series_stat_tiles.dart';
import 'issue_grid_view.dart';
import 'issue_list_view.dart';
import 'metadata_edit_sheet.dart';
import 'series_action_sheet.dart';
import 'shimmer_box.dart';
import 'cover_flight_route.dart';

class SeriesDetailPanel extends ConsumerStatefulWidget {
  final String seriesId;
  final VoidCallback? onClose;
  final Color accent;

  /// See [SeriesDetailScreen.fromReader].
  final bool fromReader;

  const SeriesDetailPanel({
    super.key,
    required this.seriesId,
    this.onClose,
    this.accent = AppTheme.accent,
    this.fromReader = false,
  });

  @override
  ConsumerState<SeriesDetailPanel> createState() => _SeriesDetailPanelState();
}

class _SeriesDetailPanelState extends ConsumerState<SeriesDetailPanel> {
  String _issueSort = 'number';
  String _issueViewMode = 'list'; // 'list' or 'grid'

  /// When the issue grid first showed for this series; tiles built within a
  /// short window of it riffle. Null until the grid builds with data.
  DateTime? _riffleFrom;

  /// Gaps seen on the last grid build, to spot issues that just arrived.
  String? _gapsSeriesId;
  Set<int> _lastMissing = const {};

  @override
  void didUpdateWidget(SeriesDetailPanel old) {
    super.didUpdateWidget(old);
    if (old.seriesId != widget.seriesId) _riffleFrom = null;
  }

  List<SeriesIssue> _sortedIssues(List<SeriesIssue> issues) {
    if (_issueSort == 'number') return issues;
    final sorted = List<SeriesIssue>.from(issues);
    const statusOrder = {'in_progress': 0, 'unread': 1, 'completed': 2};
    sorted.sort((a, b) {
      final aPriority = statusOrder[a.status] ?? 1;
      final bPriority = statusOrder[b.status] ?? 1;
      return aPriority.compareTo(bPriority);
    });
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(seriesDetailProvider(widget.seriesId));
    final serverUrl = ref.watch(activeSourceProvider.select((s) => s.baseUrl));

    return Container(
      color: context.scheme.bg,
      child: detailAsync.when(
        loading: () => _buildLoadingState(),
        error: (err, _) => _buildErrorState(err),
        data: (detail) => _buildContent(context, detail, serverUrl),
      ),
    );
  }

  Widget _buildLoadingState() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 40),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const ShimmerBox(width: 130, height: 195, radius: AppTheme.r14),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      ShimmerBox(width: 60, height: 10),
                      SizedBox(height: 10),
                      ShimmerBox(width: double.infinity, height: 24),
                      SizedBox(height: 8),
                      ShimmerBox(width: 140, height: 14),
                      SizedBox(height: 6),
                      ShimmerBox(width: 100, height: 14),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(Object err) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Failed to load: $err',
            style: TextStyle(color: context.scheme.t2)),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: () {
              // The provider streams from the mirror — a "not in mirror" error
              // only clears after a sync pull, so kick one off alongside.
              unawaited(ref
                      .read(syncEngineProvider)
                      ?.sync()
                      .catchError((_) {}) ??
                  Future.value());
              ref.invalidate(seriesDetailProvider(widget.seriesId));
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: widget.accent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text('Retry'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context, SeriesDetail detail, String serverUrl) {
    final isPanel = widget.onClose != null;
    final sortedIssues = _sortedIssues(detail.issues);

    final isOffline = !ref.watch(connectivityProvider);
    final sourceId = ref.watch(activeSourceProvider).id;
    final comicIds = detail.issues.map((i) => i.id).toList();
    final allDownloadedAsync = ref.watch(downloadedComicIdsProvider(sourceId));
    final allDownloaded = allDownloadedAsync.value ?? const <String>{};
    final downloadedComicIds =
        comicIds.where(allDownloaded.contains).toSet();
    final coverImageUrl = detail.coverUrl.isNotEmpty
        ? '$serverUrl${detail.coverUrl}'
        : null;
    final progress = detail.issueCount > 0
        ? detail.readCount / detail.issueCount
        : 0.0;

    // Determine the resume issue
    final SeriesIssue? resumeIssue;
    if (isOffline) {
      resumeIssue = detail.issues.cast<SeriesIssue?>().firstWhere(
        (i) => downloadedComicIds.contains(i!.id) &&
            (i.status == 'unread' || i.status == 'in_progress'),
        orElse: () => detail.issues.cast<SeriesIssue?>().firstWhere(
          (i) => downloadedComicIds.contains(i!.id),
          orElse: () => null,
        ),
      );
    } else {
      resumeIssue = detail.nextUnread;
    }

    return CustomScrollView(
      slivers: [
        // Header: backdrop, cover, title, metadata, resume button, progress
        SliverToBoxAdapter(
          child: SeriesDetailHeader(
            detail: detail,
            coverImageUrl: coverImageUrl,
            isPanel: isPanel,
            accent: widget.accent,
            seriesId: widget.seriesId,
            onClose: widget.onClose,
            onResume: resumeIssue != null ? () => _openIssue(detail, resumeIssue!) : null,
            onDownload: () => _downloadSeries(detail),
            showDownload: !ref.watch(isLocalSourceProvider),
            onMarkRead: () => markSeriesRead(ref: ref, detail: detail),
            // Metadata edits and file renames are Gutter-server features.
            onEditMetadata: !ref.watch(isCustomSourceProvider) ? null : () => showMetadataEditSheet(
              context: context,
              ref: ref,
              series: detail,
              seriesId: widget.seriesId,
              accent: widget.accent,
            ),
            onMore: !ref.watch(isCustomSourceProvider) ? null : () => showSeriesActionSheet(
              context: context,
              ref: ref,
              detail: detail,
              seriesId: widget.seriesId,
              accent: widget.accent,
              // Close the iPad split-view panel after a successful rename so
              // the stale panel (wrong series ID) is cleared.
              onFolderRenamed: widget.onClose,
            ),
            resumeButtonContent: _buildResumeLabel(resumeIssue, isOffline, oneShot: detail.issueCount == 1),
            progress: progress,
          ),
        ),

        // Next-up card + stat tiles
        SliverToBoxAdapter(
          child: _buildNextUpAndStats(detail, resumeIssue, serverUrl),
        ),

        // Issues header with view toggle + sort
        SliverToBoxAdapter(
          child: detail.issueCount > 1 ? _buildIssuesHeader() : const SizedBox.shrink(),
        ),

        // Issue list / grid
        SliverPadding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, isPanel ? 40 : 120),
          sliver: _buildIssueSliver(
            sortedIssues: sortedIssues,
            detail: detail,
            serverUrl: serverUrl,
            isOffline: isOffline,
            downloadedComicIds: downloadedComicIds,
          ),
        ),
      ],
    );
  }

  Widget _buildNextUpAndStats(SeriesDetail detail, SeriesIssue? resumeIssue, String serverUrl) {
    // One issue: the resume button already says everything these would.
    if (detail.issueCount <= 1) return const SizedBox(height: 8);
    if (resumeIssue == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
        child: SeriesStatTiles(detail: detail),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Column(
        children: [
          NextUpCard(
            issue: resumeIssue,
            accent: widget.accent,
            coverImageUrl: ref.watch(issueCoverUrlProvider(resumeIssue.id)),
            onTap: () => _openIssue(detail, resumeIssue),
          ),
          const SizedBox(height: 12),
          SeriesStatTiles(detail: detail),
        ],
      ),
    );
  }

  Widget _buildResumeLabel(SeriesIssue? resumeIssue, bool isOffline, {required bool oneShot}) {
    final ink = Scheme.onAccent(widget.accent);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.play_arrow_rounded, size: 20, color: ink),
        const SizedBox(width: 8),
        Flexible(child: Text(
          resumeIssue != null
              ? '${resumeIssue.status == 'completed' ? 'Read' : resumeIssue.status == 'unread' && resumeIssue.currentPage == null ? 'Start' : 'Resume'}${oneShot ? '' : ' ${resumeIssue.displayName}'}${resumeIssue.currentPage != null && resumeIssue.status != 'completed' ? ' · P.${resumeIssue.currentPage! + 1}' : ''}'
              : isOffline ? 'No Downloaded Issues' : 'All Read',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: ink),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        )),
        if (resumeIssue != null &&
            resumeIssue.currentPage != null &&
            resumeIssue.totalPages != null) ...[
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: ink.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(AppTheme.pill),
            ),
            child: Text(
              '${(resumeIssue.currentPage! / resumeIssue.totalPages! * 100).round()}%',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: ink),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildIssuesHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 1, 20, 3),
      child: Row(
        children: [
          const Text('Issues', style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
          )),
          const Spacer(),
          // View toggle. Each half takes taps over a 44pt-tall box around the
          // 30pt pill; the header's vertical padding is trimmed 7pt to match.
          SizedBox(
            height: 44,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: context.scheme.s1,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _viewToggleButton(Icons.grid_view_rounded, 'grid'),
                      _viewToggleButton(Icons.view_list_rounded, 'list'),
                    ],
                  ),
                ),
                Positioned.fill(
                  child: Row(children: [
                    _viewToggleHitArea('grid'),
                    _viewToggleHitArea('list'),
                  ]),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Sort button
          GestureDetector(
            onTap: () {
              setState(() {
                _issueSort = _issueSort == 'number' ? 'status' : 'number';
              });
            },
            child: Container(
              height: 30,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: context.scheme.s2,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(
                  color: context.scheme.borderFaint,
                  width: 0.5,
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.swap_vert, size: 13, color: context.scheme.t2),
                  const SizedBox(width: 6),
                  Text(
                    _issueSort == 'number' ? 'By Number' : 'By Status',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: context.scheme.t2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _setViewMode(String mode) => setState(() {
        // Switching into the grid riffles it, like opening the series.
        if (mode == 'grid' && _issueViewMode != 'grid') _riffleFrom = null;
        _issueViewMode = mode;
      });

  Widget _viewToggleButton(IconData icon, String mode) {
    final active = _issueViewMode == mode;
    return Container(
      width: 28,
      height: 24,
      decoration: BoxDecoration(
        color: active ? context.scheme.s3 : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Icon(icon, size: 12, color: active ? context.scheme.tx : context.scheme.t3),
    );
  }

  /// The tappable half of the view toggle, full height of the 44pt box.
  Widget _viewToggleHitArea(String mode) => Expanded(
        child: Semantics(
          button: true,
          selected: _issueViewMode == mode,
          label: mode == 'grid' ? 'Grid view' : 'List view',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _setViewMode(mode),
          ),
        ),
      );

  Widget _buildIssueSliver({
    required List<SeriesIssue> sortedIssues,
    required SeriesDetail detail,
    required String serverUrl,
    required bool isOffline,
    required Set<String> downloadedComicIds,
  }) {
    if (_issueViewMode == 'grid') {
      // Gap placeholders only make sense in number order.
      final missing = _issueSort == 'number'
          ? missingIssueNumbers(detail.issues)
          : const <int>[];
      final entries = withGaps(sortedIssues, missing);

      // Issues that filled a gap since the last build pop into place.
      final arrived = <String>{};
      if (_gapsSeriesId == widget.seriesId && _lastMissing.isNotEmpty) {
        for (final issue in detail.issues) {
          final n = int.tryParse(issue.number?.trim() ?? '');
          if (n != null && _lastMissing.contains(n)) arrived.add(issue.id);
        }
      }
      _gapsSeriesId = widget.seriesId;
      _lastMissing = missing.toSet();

      // Riffle only the tiles built right after the grid first shows.
      final riffleFrom = _riffleFrom ??= DateTime.now();
      final riffle =
          DateTime.now().difference(riffleFrom) < const Duration(milliseconds: 600);

      return SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: LayoutBreakpoint.isTablet(context) ? 4 : 3,
          crossAxisSpacing: 12,
          mainAxisSpacing: 14,
          childAspectRatio: 0.58,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final entry = entries[index];
            if (entry.isMissing) {
              return RiffleEntry(
                index: index,
                play: riffle,
                child: MissingIssueSlot(
                  number: entry.missingNumber!,
                  accent: widget.accent,
                ),
              );
            }
            final issue = entry.issue!;
            final isDownloaded = !isOffline || downloadedComicIds.contains(issue.id);
            final Widget tile = IssueGridTile(
              issue: issue,
              serverUrl: serverUrl,
              accent: widget.accent,
              onTap: () => _openIssue(detail, issue),
              onLongPress: () => showIssueActionSheet(
                context: context, ref: ref, issue: issue,
                seriesId: widget.seriesId, accent: widget.accent,
              ),
            );
            return RiffleEntry(
              index: index,
              play: riffle,
              child: PopIn(
                play: arrived.contains(issue.id),
                child: isDownloaded
                    ? tile
                    : Opacity(opacity: 0.4, child: AbsorbPointer(child: tile)),
              ),
            );
          },
          childCount: entries.length,
        ),
      );
    }

    // List mode — 2 columns only when each row gets enough width for a
    // readable title (iPad portrait and the split-view panel drop to 1).
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        // 820pt is the design's two-column breakpoint for the issue list.
        if (constraints.crossAxisExtent < 820) {
          return SliverList(
            delegate: _issueListDelegate(sortedIssues, detail, serverUrl, isOffline, downloadedComicIds),
          );
        }
        return SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 8,
            mainAxisSpacing: 2,
            mainAxisExtent: 76,
          ),
          delegate: _issueListDelegate(sortedIssues, detail, serverUrl, isOffline, downloadedComicIds),
        );
      },
    );
  }

  SliverChildBuilderDelegate _issueListDelegate(
    List<SeriesIssue> sortedIssues,
    SeriesDetail detail,
    String serverUrl,
    bool isOffline,
    Set<String> downloadedComicIds,
  ) {
    return SliverChildBuilderDelegate(
      (context, index) {
        final issue = sortedIssues[index];
        final isDownloaded = !isOffline || downloadedComicIds.contains(issue.id);
        final row = IssueListRow(
          issue: issue,
          serverUrl: serverUrl,
          seriesId: widget.seriesId,
          seriesName: detail.name,
          accent: widget.accent,
          onTap: () => _openIssue(detail, issue),
          onLongPress: () => showIssueActionSheet(
            context: context, ref: ref, issue: issue,
            seriesId: widget.seriesId, accent: widget.accent,
          ),
        );
        if (!isDownloaded) {
          return Opacity(opacity: 0.4, child: AbsorbPointer(child: row));
        }
        return row;
      },
      childCount: sortedIssues.length,
    );
  }

  void _openIssue(SeriesDetail detail, SeriesIssue issue) {
    final issueIndex = detail.issues.indexOf(issue);
    final route = readerRoute<void>(
      context,
      comicId: issue.id,
      builder: (_) => ReaderScreen(
        comicId: issue.id,
        comicPath: issue.name,
        initialPage: issue.currentPage ?? 0,
        seriesIssues: detail.issues,
        currentIssueIndex: issueIndex >= 0 ? issueIndex : 0,
        seriesId: widget.seriesId,
        seriesName: detail.name,
      ),
    );
    final nav = Navigator.of(context);
    if (widget.fromReader) {
      // Over a reader: drop this page, then replace that reader. Stacking a
      // second reader would leave the first holding stale progress (its next
      // save overwrites the newer one) and running its session/wakelock.
      nav.pop(SeriesDetailScreen.replacedResult);
      nav.pushReplacement(route);
    } else {
      nav.push(route);
    }
  }

  Future<void> _downloadSeries(SeriesDetail detail) async {
    if (!requirePro(context, ref, reason: 'Downloads are part of Pro.')) return;
    HapticFeedback.mediumImpact();
    final source = ref.read(activeSourceProvider);
    final manager = ref.read(downloadManagerProvider);
    if (manager == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Downloads initializing, try again in a moment'),
            backgroundColor: context.scheme.s2,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            duration: const Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    final headers = {
      'Content-Type': 'application/json',
      'X-Device-ID': ref.read(serverConfigProvider).deviceId,
    };
    final picked = await showSeriesDownloadSheet(
      context,
      detail: detail,
      source: source,
      // Auth only for the size probe; enqueue gets [headers] so the journal
      // never stores credentials (DownloadManager adds auth at fetch time).
      headers: {...headers, ...source.authHeaders},
      onDevice: ref.read(onDeviceProvider).comicIds,
      accent: widget.accent,
    );
    if (picked == null) return;
    for (final issue in picked) {
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
}
