import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_theme.dart';
import '../config/comic_style.dart';
import '../config/layout_breakpoint.dart';
import '../config/scheme.dart';
import '../models/arc.dart';
import '../models/series.dart';
import '../providers/accent_provider.dart';
import '../providers/arc_provider.dart';
import '../services/arc_shelves.dart';
import '../widgets/shimmer_box.dart';
import 'arc_common.dart';
import 'series_detail_screen.dart';

/// Reading-order lists longer than this show a window around the current
/// issue until "Show all" is tapped.
const _pageSize = 20;

class ArcDetailScreen extends ConsumerStatefulWidget {
  final Arc arc;
  const ArcDetailScreen({super.key, required this.arc});

  @override
  ConsumerState<ArcDetailScreen> createState() => _ArcDetailScreenState();
}

class _ArcDetailScreenState extends ConsumerState<ArcDetailScreen> {
  bool _showAll = false;
  // Lives here, not in _Summary, so it survives the summary scrolling out
  // of the lazy list.
  bool _summaryExpanded = false;

  @override
  Widget build(BuildContext context) {
    final arc = widget.arc;
    final issuesAsync = ref.watch(arcIssuesProvider(arc.id));
    final accent = ref.watch(accentProvider).value ?? AppTheme.accent;
    final comic = ComicTokens.watch(ref, context, accent);
    final tablet = LayoutBreakpoint.isTablet(context);
    final gutter = tablet ? 32.0 : 16.0;
    return Scaffold(
      backgroundColor: context.scheme.bg,
      appBar: AppBar(backgroundColor: context.scheme.bg),
      body: issuesAsync.when(
        loading: () => Padding(
          padding: EdgeInsets.all(gutter),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ShimmerBox(width: 150, height: 225),
              SizedBox(height: 20),
              ShimmerBox(width: 240, height: 28),
              SizedBox(height: 10),
              ShimmerBox(width: 180, height: 14),
            ],
          ),
        ),
        error: (e, _) => Center(
          child: Text(
            'Failed to load issues: $e',
            style: TextStyle(color: context.scheme.t2),
          ),
        ),
        data: (issues) {
          if (issues.isEmpty) {
            return Center(
              child: Text(
                "None of this arc's issues are in your library yet",
                style: TextStyle(color: context.scheme.t2),
              ),
            );
          }
          final current = arcCurrentIndex(issues);
          final paged = !_showAll && issues.length > _pageSize;
          final start =
              paged ? arcWindowStart(issues.length, current, size: _pageSize) : 0;
          final end = paged ? start + _pageSize : issues.length;
          return ListView(
            padding: EdgeInsets.fromLTRB(gutter, 0, gutter, 120),
            children: [
              _Header(
                arc: arc,
                issues: issues,
                current: current,
                accent: accent,
                comic: comic,
                tablet: tablet,
              ),
              const SizedBox(height: 22),
              if (arc.description.isNotEmpty) ...[
                _Summary(
                  text: arc.description,
                  accent: accent,
                  expanded: _summaryExpanded,
                  onToggle: () => setState(
                      () => _summaryExpanded = !_summaryExpanded),
                ),
                const SizedBox(height: 22),
              ],
              _SeriesChips(issues: issues),
              const SizedBox(height: 30),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Reading order',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.displayTextStyle(comic, fontSize: 26)
                          .copyWith(color: context.scheme.tx),
                    ),
                  ),
                  if (paged)
                    Text(
                      '${start + 1}–$end OF ${issues.length}',
                      style: context.monoLabel.copyWith(fontSize: 11),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              for (var i = start; i < end; i++)
                _IssueRow(
                  issue: issues[i],
                  position: i + 1,
                  isCurrent: i == current,
                  accent: accent,
                  tablet: tablet,
                  onTap: () => openArcIssue(context, arc, issues, i),
                ),
              if (paged)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Center(
                    child: TextButton(
                      onPressed: () => setState(() => _showAll = true),
                      child: Text(
                        'Show all ${issues.length} issues',
                        style: TextStyle(
                          color: accent,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final Arc arc;
  final List<SeriesIssue> issues;
  final int current;
  final Color accent;
  final ComicTokens comic;
  final bool tablet;
  const _Header({
    required this.arc,
    required this.issues,
    required this.current,
    required this.accent,
    required this.comic,
    required this.tablet,
  });

  @override
  Widget build(BuildContext context) {
    final name = arcDisplayName(arc.name);
    // Counted from the live issue list rather than the (navigation-time)
    // Arc snapshot so the header updates after reading.
    final read = issues.where((i) => i.status == 'completed').length;
    final align = tablet ? TextAlign.start : TextAlign.center;
    final coverW = tablet ? 200.0 : 150.0;
    final cover = Container(
      decoration: BoxDecoration(
        border: Border.all(color: context.scheme.ink, width: 2),
        borderRadius: BorderRadius.circular(AppTheme.r8),
        boxShadow: [BoxShadow(color: accent, offset: const Offset(6, 6))],
      ),
      child: ArcCover(
        url: arc.coverUrl,
        width: coverW - 4,
        height: coverW * 1.5 - 4,
        radius: AppTheme.r8 - 2,
      ),
    );
    final button = FilledButton.icon(
      onPressed: () =>
          openArcIssue(context, arc, issues, current < 0 ? 0 : current),
      icon: const Icon(Icons.play_arrow_rounded, size: 20),
      label: Text(arcPrimaryLabel(issues)),
      style: FilledButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: Scheme.onAccent(accent),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        shape: const StadiumBorder(),
      ),
    );
    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (name.kicker.isNotEmpty) ...[
          Text(
            name.kicker,
            textAlign: align,
            style: AppTheme.monoLabel.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.9,
              color: accent,
            ),
          ),
          const SizedBox(height: 8),
        ],
        Text(
          name.title,
          textAlign: align,
          style: AppTheme.displayTextStyle(comic, fontSize: tablet ? 60 : 44)
              .copyWith(color: context.scheme.tx, height: 1),
        ),
        const SizedBox(height: 8),
        Text(
          arcMetaLine(arc),
          textAlign: align,
          style: context.monoLabel.copyWith(fontSize: 12, letterSpacing: 1.2),
        ),
        const SizedBox(height: 18),
        Text(
          'READ $read OF ${issues.length}',
          textAlign: align,
          style: AppTheme.monoLabel.copyWith(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.1,
            color: context.scheme.t2,
          ),
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppTheme.pill),
          child: LinearProgressIndicator(
            value: read / issues.length,
            minHeight: 6,
            backgroundColor: context.scheme.s2,
            color: accent,
          ),
        ),
        const SizedBox(height: 20),
        if (tablet) Align(alignment: Alignment.centerLeft, child: button)
        else button,
      ],
    );
    if (!tablet) {
      return Column(children: [cover, const SizedBox(height: 28), info]);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [cover, const SizedBox(width: 28), Expanded(child: info)],
    );
  }
}

/// Arc description clamped to four lines, with a More/Less toggle when it
/// actually overflows.
class _Summary extends StatelessWidget {
  static const _maxLines = 4;
  final String text;
  final Color accent;
  final bool expanded;
  final VoidCallback onToggle;
  const _Summary({
    required this.text,
    required this.accent,
    required this.expanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      color: context.scheme.t2,
      fontSize: 15,
      height: 1.5,
    );
    return LayoutBuilder(builder: (context, c) {
      final overflows = (TextPainter(
        text: TextSpan(text: text, style: style),
        maxLines: _maxLines,
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout(maxWidth: c.maxWidth))
          .didExceedMaxLines;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            text,
            style: style,
            maxLines: expanded ? null : _maxLines,
            overflow: expanded ? null : TextOverflow.ellipsis,
          ),
          if (overflows)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  expanded ? 'Less' : 'More',
                  style: TextStyle(
                    color: accent,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      );
    });
  }
}

/// One chip per series in the arc (first-appearance order) opening that
/// series' detail page.
class _SeriesChips extends StatelessWidget {
  final List<SeriesIssue> issues;
  const _SeriesChips({required this.issues});

  @override
  Widget build(BuildContext context) {
    final names = <String, String>{};
    final counts = <String, int>{};
    for (final i in issues) {
      final id = i.seriesId;
      if (id == null) continue;
      names.putIfAbsent(id, () => i.seriesName ?? 'Unknown series');
      counts[id] = (counts[id] ?? 0) + 1;
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final id in names.keys)
          GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SeriesDetailScreen(seriesId: id),
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: context.scheme.s1,
                border: Border.all(color: context.scheme.hairStrong),
                borderRadius: BorderRadius.circular(AppTheme.r18),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      names[id]!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: context.scheme.tx, fontSize: 14),
                    ),
                  ),
                  Text(
                    ' · ${counts[id]}',
                    style: TextStyle(color: context.scheme.t3, fontSize: 14),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 16,
                    color: context.scheme.t3,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _IssueRow extends StatelessWidget {
  final SeriesIssue issue;
  final int position;
  final bool isCurrent;
  final Color accent;
  final bool tablet;
  final VoidCallback onTap;
  const _IssueRow({
    required this.issue,
    required this.position,
    required this.isCurrent,
    required this.accent,
    required this.tablet,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final completed = issue.status == 'completed';
    final cur = issue.currentPage ?? 0;
    final total = issue.totalPages ?? 0;
    final inProgress = issue.status == 'in_progress' && total > 0;
    final coverW = tablet ? 56.0 : 48.0;
    final dim = completed ? 0.6 : 1.0;
    final date = arcCoverDate(issue.coverDate);
    final title = issue.title ?? '';

    final Widget trailing;
    if (completed) {
      trailing = const Icon(
        Icons.check_circle_outline_rounded,
        size: 22,
        color: AppTheme.green,
      );
    } else if (inProgress) {
      trailing = Text(
        'P.$cur / $total',
        style: AppTheme.monoLabel.copyWith(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: accent,
        ),
      );
    } else {
      trailing = Icon(
        Icons.radio_button_unchecked_rounded,
        size: 22,
        color: context.scheme.t4,
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: isCurrent
              ? BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  border: Border.all(color: accent),
                  borderRadius: BorderRadius.circular(10),
                )
              : BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: context.scheme.hair),
                  ),
                ),
          child: Row(
            children: [
              SizedBox(
                width: 28,
                child: Text(
                  position.toString().padLeft(2, '0'),
                  style: AppTheme.monoLabel.copyWith(
                    fontWeight: FontWeight.w600,
                    color: isCurrent ? accent : context.scheme.t3,
                  ),
                ),
              ),
              SizedBox(width: tablet ? 12 : 8),
              Opacity(
                opacity: dim,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppTheme.r4),
                  child: SizedBox(
                    width: coverW,
                    height: coverW * 1.5,
                    child: Stack(
                      children: [
                        ArcCover(
                          comicId: issue.id,
                          url: issue.coverUrl,
                          width: coverW,
                          height: coverW * 1.5,
                          radius: 0,
                          placeholderIcon: Icons.menu_book_rounded,
                        ),
                        if (inProgress)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            height: 4,
                            child: ColoredBox(
                              color: Colors.black54,
                              child: FractionallySizedBox(
                                alignment: Alignment.centerLeft,
                                widthFactor: (cur / total).clamp(0.0, 1.0),
                                child: ColoredBox(color: accent),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(width: tablet ? 16 : 12),
              Expanded(
                child: Opacity(
                  opacity: dim,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        arcIssueHeading(issue),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.scheme.tx,
                          fontSize: tablet ? 17 : 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (title.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.scheme.t2,
                            fontSize: tablet ? 14 : 13,
                          ),
                        ),
                      ],
                      if (date.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          date,
                          style: context.monoLabel.copyWith(
                            fontSize: 11,
                            letterSpacing: 0.9,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              trailing,
            ],
          ),
        ),
      ),
    );
  }
}
