// lib/widgets/series_detail_header.dart
import 'dart:ui';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../config/app_theme.dart';
import '../config/comic_style.dart';
import '../config/layout_breakpoint.dart';
import '../config/scheme.dart';
import '../models/series.dart';
import '../services/mirror/library_view.dart' show splitCreators;
import 'caption_box.dart';
import 'corner_box.dart';
import 'creator_detail_panel.dart' show openCreator;
import 'glass_button.dart';
import 'halftone_overlay.dart';
import 'panel_frame.dart';
import 'series_progress_bar.dart';
import 'series_enrichment_section.dart';
import 'shine_overlay.dart';

class SeriesDetailHeader extends ConsumerWidget {
  final SeriesDetail detail;
  final String? coverImageUrl;
  final bool isPanel;
  final Color accent;
  final String seriesId;
  final VoidCallback? onClose;
  final VoidCallback? onResume;
  final VoidCallback? onDownload;
  final VoidCallback? onMarkRead;
  final VoidCallback? onEditMetadata;
  final VoidCallback? onMore;
  final Widget resumeButtonContent;
  final double progress;

  /// Cover shadow from the design handoff: `0 24 60 rgba(0,0,0,.5)`.
  static const _coverShadow = [
    BoxShadow(
      color: Color(0x80000000),
      offset: Offset(0, 24),
      blurRadius: 60,
    ),
  ];

  const SeriesDetailHeader({
    super.key,
    required this.detail,
    required this.coverImageUrl,
    required this.isPanel,
    required this.accent,
    required this.seriesId,
    this.onClose,
    this.onResume,
    this.onDownload,
    this.onMarkRead,
    this.onEditMetadata,
    this.onMore,
    required this.resumeButtonContent,
    required this.progress,
  });

  String _estimateReadTime(SeriesDetail detail) {
    int totalPages = 0;
    int counted = 0;
    for (final issue in detail.issues) {
      if (issue.totalPages != null) {
        totalPages += issue.totalPages!;
        counted++;
      }
    }

    int minutes;
    if (counted > 0) {
      final avgPages = totalPages / counted;
      final estimatedTotal = (avgPages * detail.issueCount).round();
      minutes = (estimatedTotal * 15 / 60).round(); // 15s per page
    } else {
      minutes = detail.issueCount * 12; // fallback: 12min/issue
    }

    if (minutes >= 60) {
      return '~${minutes ~/ 60}h ${minutes % 60}m';
    }
    return '~${minutes}m';
  }

  /// Derives the series status caption from read progress.
  ///
  /// The backend exposes no publication-status field (no "ongoing" vs
  /// "complete run" signal) — see `SeriesDetail` in lib/models/series.dart
  /// and the backend API list in CLAUDE.md. The only honest thing we can
  /// derive from what's available is reading completion: all owned issues
  /// read (`readCount >= issueCount`, with at least one issue) means the
  /// reader has finished the series, so we show FINISHED. Any other state
  /// (partially read, unread, or no issues) has no truthful caption to
  /// show, so this returns null rather than guessing "ONGOING".
  static String? statusCaption(SeriesDetail detail) {
    if (detail.issueCount > 0 && detail.readCount >= detail.issueCount) {
      return 'FINISHED';
    }
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final comic = ComicTokens.watch(ref, context, accent);
    final backdropHeight = isPanel ? 380.0 : 440.0;
    final backdropOpacity = context.scheme.dark ? 0.75 : 0.45;
    return Stack(
      children: [
        // Blurred cover background
        if (coverImageUrl != null)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: backdropHeight,
            // Clip: the blur + 1.3x scale otherwise bleed past the gradient
            // and leave a hard seam under a tall hero.
            child: ClipRect(child: Stack(
              fit: StackFit.expand,
              children: [
                ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 70, sigmaY: 70),
                  child: Transform.scale(
                    scale: 1.3,
                    child: Opacity(
                      opacity: backdropOpacity,
                      child: CachedNetworkImage(
                        imageUrl: coverImageUrl!,
                        fit: BoxFit.cover,
                        placeholder: (_, _) => Container(color: context.scheme.s1),
                        errorWidget: (_, _, _) => Container(color: context.scheme.s1),
                      ),
                    ),
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.15),
                        Colors.black.withValues(alpha: 0.5),
                        context.scheme.bg.withValues(alpha: 0.95),
                        context.scheme.bg,
                      ],
                      stops: const [0.0, 0.4, 0.8, 1.0],
                    ),
                  ),
                ),
                const HalftoneOverlay(opacity: 0.08),
              ],
            )),
          ),

        // Content
        SafeArea(
          bottom: false,
          child: Column(
            children: [
              // Top actions
              _buildTopActions(context),

              // Hero section
              if (isPanel) ...[
                _buildPanelHero(context, ref, comic),
              ] else ...[
                _buildFullScreenHero(context, ref, comic),
              ],

              // Resume button
              _buildResumeButton(),

              // Secondary actions row
              _buildSecondaryActions(context),

              // Series progress section — meaningless for a single issue.
              if (detail.issueCount > 1) _buildProgressSection(context),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTopActions(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (isPanel)
            const SizedBox(width: 36)
          else
            GlassButton(
              onTap: () => Navigator.pop(context),
              child: Icon(Icons.chevron_left, size: 18, color: context.scheme.tx),
            ),
          Row(
            children: [
              if (!isPanel) ...[
                GlassButton(
                  child: Icon(Icons.favorite_border, size: 16, color: context.scheme.tx),
                ),
                const SizedBox(width: 8),
                GlassButton(
                  onTap: onMore,
                  child: Icon(Icons.more_horiz, size: 16, color: context.scheme.tx),
                ),
              ],
              if (isPanel) ...[
                GlassButton(
                  onTap: onMore,
                  child: Icon(Icons.more_horiz, size: 16, color: context.scheme.tx),
                ),
                const SizedBox(width: 8),
                GlassButton(
                  onTap: onClose,
                  child: Icon(Icons.close, size: 16, color: context.scheme.tx),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// `Publisher · years` mono caption line. Null when there's nothing to show.
  Widget? _buildPublisherLine(BuildContext context, double fontSize) {
    final parts = <String>[];
    if (detail.publisher != null && detail.publisher!.isNotEmpty) {
      parts.add(detail.publisher!);
    }
    if (detail.startYear != null) {
      parts.add('${detail.startYear}');
    } else if (detail.year != null) {
      parts.add('${detail.year}');
    }
    if (parts.isEmpty) return null;
    return Text(
      parts.join(' · '),
      style: context.monoCaption.copyWith(fontSize: fontSize),
    );
  }

  /// Whether [_Byline] would render anything for [detail] — mirrors the
  /// null-check the old `_buildBylineText` used to do, kept cheap so the
  /// caller can skip the spacer without building the recognizer-bearing
  /// widget itself.
  static bool _hasByline(SeriesDetail detail) {
    final writer = detail.creators.isEmpty ? detail.writer : null;
    final artist = detail.creators.isEmpty ? detail.penciller : null;
    return writer != null || artist != null;
  }

  Widget _buildGenreChips(BuildContext context, ComicTokens comic) {
    if (detail.genres.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: detail.genres.map((genre) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: context.scheme.s1,
            borderRadius: BorderRadius.circular(AppTheme.r8),
            border: Border.all(color: comic.ink, width: comic.borderWidth),
          ),
          child: Text(
            genre,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: context.scheme.t2,
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildPanelHero(BuildContext context, WidgetRef ref, ComicTokens comic) {
    final status = statusCaption(detail);
    final publisherLine = _buildPublisherLine(context, 10);
    final hasByline = _hasByline(detail);
    return Column(
      children: [
        // Cover centered above
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Center(
            child: PanelFrame(
              radius: AppTheme.r14,
              extraShadows: _coverShadow,
              child: SizedBox(
                width: 150,
                height: 225,
                child: coverImageUrl != null
                    ? CachedNetworkImage(
                        imageUrl: coverImageUrl!,
                        fit: BoxFit.cover,
                      )
                    : Container(color: context.scheme.s1),
              ),
            ),
          ),
        ),
        // Title + metadata below
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (status != null) ...[
                CaptionBox(text: status, comic: comic),
                const SizedBox(height: 6),
              ],
              if (publisherLine != null) ...[
                publisherLine,
                const SizedBox(height: 6),
              ],
              Text(detail.name,
                textAlign: TextAlign.center,
                style: AppTheme.displayTextStyle(comic, fontSize: 30),
              ),
              if (hasByline) ...[
                const SizedBox(height: 8),
                _Byline(detail: detail),
              ],
              const SizedBox(height: 12),
              _buildMetaRow(context, 11),
              if (detail.genres.isNotEmpty) ...[
                const SizedBox(height: 10),
                _buildGenreChips(context, comic),
              ],
              Align(
                alignment: Alignment.centerLeft,
                child: SeriesEnrichmentSection(
                  accent: accent,
                  description: detail.description,
                  creators: detail.creators,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFullScreenHero(BuildContext context, WidgetRef ref, ComicTokens comic) {
    final status = statusCaption(detail);
    final publisherLine = _buildPublisherLine(context, 10);
    final hasByline = _hasByline(detail);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Hero(
            tag: 'cover-series-$seriesId',
            child: Material(
              type: MaterialType.transparency,
              child: PanelFrame(
                radius: AppTheme.r14,
                extraShadows: _coverShadow,
                child: SizedBox(
                  width: LayoutBreakpoint.isTablet(context) ? 200 : 128,
                  height: LayoutBreakpoint.isTablet(context) ? 300 : 192,
                  child: coverImageUrl != null
                      ? CachedNetworkImage(
                          imageUrl: coverImageUrl!,
                          fit: BoxFit.cover,
                        )
                      : Container(color: context.scheme.s1),
                ),
              ),
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (status != null) ...[
                    CaptionBox(text: status, comic: comic),
                    const SizedBox(height: 6),
                  ],
                  if (publisherLine != null) ...[
                    publisherLine,
                    const SizedBox(height: 6),
                  ],
                  Builder(builder: (context) => Text(detail.name, style: AppTheme.displayTextStyle(
                    comic,
                    fontSize: LayoutBreakpoint.isTablet(context) ? 40 : 28,
                  ))),
                  if (hasByline) ...[
                    const SizedBox(height: 8),
                    _Byline(detail: detail),
                  ],
                  const SizedBox(height: 12),
                  _buildMetaRow(context, 11),
                  if (detail.genres.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _buildGenreChips(context, comic),
                  ],
                  SeriesEnrichmentSection(
                  accent: accent,
                    description: detail.description,
                    creators: detail.creators,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetaRow(BuildContext context, double fontSize) {
    return Row(
      children: [
        Icon(Icons.auto_stories_rounded, size: 11, color: context.scheme.t3),
        const SizedBox(width: 4),
        Text('${detail.issueCount}', style: context.monoCaption.copyWith(
          fontSize: fontSize, fontWeight: FontWeight.w600, color: context.scheme.t2)),
        const SizedBox(width: 14),
        Icon(Icons.access_time_rounded, size: 11, color: context.scheme.t3),
        const SizedBox(width: 4),
        Text(_estimateReadTime(detail), style: context.monoCaption.copyWith(
          fontSize: fontSize, fontWeight: FontWeight.w600, color: context.scheme.t2)),
      ],
    );
  }

  Widget _buildResumeButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: GestureDetector(
        onTap: onResume,
        child: Container(
          height: isPanel ? 48 : 56,
          clipBehavior: Clip.hardEdge,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                accent,
                accent.withValues(alpha: 0.85),
              ],
            ),
            borderRadius: BorderRadius.circular(AppTheme.r18),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.4),
                offset: const Offset(0, 10),
                blurRadius: 24,
              ),
              BoxShadow(
                color: Colors.white.withValues(alpha: 0.3),
                offset: const Offset(0, 1),
                blurRadius: 0,
              ),
            ],
          ),
          child: Stack(
            children: [
              Center(child: resumeButtonContent),
              const ShineOverlay(),
            ],
          ),
        ),
      ),
    );
  }

  /// Download / Mark Read / Favorite / edit. A third of a split-view panel or
  /// a phone is narrower than "Mark Read" set beside its icon, so below
  /// [_stackBelow] per button the icon sits above a smaller label instead.
  static const double _stackBelow = 120;

  Widget _buildSecondaryActions(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: LayoutBuilder(builder: (context, constraints) {
        // Three flexible buttons, the square edit button, three 8pt gaps.
        final cell = (constraints.maxWidth - 42 - 3 * 8) / 3;
        final stacked = cell < _stackBelow;
        final height = stacked ? 52.0 : 42.0;
        return Row(
          children: [
            Expanded(
              child: _actionButton(context, Icons.download_rounded, 'Download',
                  onDownload, stacked, height),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _actionButton(context, Icons.check_circle_outline,
                  'Mark Read', onMarkRead, stacked, height),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _actionButton(context, Icons.bookmark_border, 'Favorite',
                  null, stacked, height),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: 'Edit Metadata',
              child: GestureDetector(
                onTap: onEditMetadata,
                child: Container(
                  height: height,
                  width: 42,
                  decoration: _actionDecoration(context),
                  child: Icon(Icons.edit_note, size: 18, color: context.scheme.t2),
                ),
              ),
            ),
          ],
        );
      }),
    );
  }

  BoxDecoration _actionDecoration(BuildContext context) => BoxDecoration(
        color: context.scheme.s1,
        borderRadius: BorderRadius.circular(AppTheme.r14),
        border: Border.all(color: context.scheme.borderFaint, width: 0.5),
      );

  Widget _actionButton(BuildContext context, IconData icon, String label,
      VoidCallback? onTap, bool stacked, double height) {
    final t2 = context.scheme.t2;
    final text = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
          fontSize: stacked ? 11 : 13, fontWeight: FontWeight.w600, color: t2),
    );
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: _actionDecoration(context),
        child: stacked
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 16, color: t2),
                  const SizedBox(height: 3),
                  text,
                ],
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 16, color: t2),
                  const SizedBox(width: 6),
                  Flexible(child: text),
                ],
              ),
      ),
    );
  }

  Widget _buildProgressSection(BuildContext context) {
    final left = detail.issueCount - detail.readCount;
    final years = seriesRunYears(
      detail.issues.map((i) => coverYear(i.coverDate)),
      fallback: detail.startYear ?? detail.year,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Corner-box stats badge: issue count big, run years and the
          // read/left split in the stack.
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
            child: CornerBox(
              band: 'Series',
              bandColor: accent,
              big: '${detail.issueCount}',
              bigCaption: detail.issueCount == 1 ? 'Issue' : 'Issues',
              stack: [
                ?years,
                '${detail.readCount} read',
                left > 0 ? '$left left' : 'complete',
              ],
              accent: accent,
            ),
          ),
          const SizedBox(height: 14),
          SeriesProgressBar(
            total: detail.issueCount,
            read: detail.readCount,
            currentIndex: detail.readCount < detail.issueCount ? detail.readCount : null,
            accent: accent,
          ),
        ],
      ),
    );
  }
}

/// `by Writer & Artist` line, extracted into its own State so the
/// [TapGestureRecognizer]s it creates (one per name) get disposed instead of
/// leaking — a bare [ConsumerWidget] has nowhere to call `dispose()`.
/// Falls back to writer-only or artist-only. These are raw ComicInfo strings
/// (possibly comma-joined, e.g. "Tom King, Scott Snyder") with no creator
/// id, so every name opens via id-0 lookup (see openCreator).
class _Byline extends ConsumerStatefulWidget {
  final SeriesDetail detail;
  const _Byline({required this.detail});

  @override
  ConsumerState<_Byline> createState() => _BylineState();
}

class _BylineState extends ConsumerState<_Byline> {
  final List<TapGestureRecognizer> _recognizers = [];

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Rebuilding (e.g. a theme change) replaces every span, so the previous
    // build's recognizers must go first or they'd leak just the same.
    _disposeRecognizers();

    final detail = widget.detail;
    final writer = detail.creators.isEmpty ? detail.writer : null;
    final artist = detail.creators.isEmpty ? detail.penciller : null;

    final style = TextStyle(color: context.scheme.t2, fontSize: 13, fontWeight: FontWeight.w500);
    final spans = <InlineSpan>[const TextSpan(text: 'by ')];
    void addNames(String raw) {
      final names = splitCreators(raw);
      final list = names.isEmpty ? [raw] : names;
      for (var i = 0; i < list.length; i++) {
        if (i > 0) spans.add(const TextSpan(text: ', '));
        final name = list[i];
        final recognizer = TapGestureRecognizer()
          ..onTap = () => openCreator(context, ref, id: 0, name: name);
        _recognizers.add(recognizer);
        spans.add(TextSpan(text: name, recognizer: recognizer));
      }
    }

    if (writer != null) addNames(writer);
    if (writer != null && artist != null) spans.add(const TextSpan(text: ' & '));
    if (artist != null) addNames(artist);

    return Text.rich(TextSpan(style: style, children: spans));
  }
}
