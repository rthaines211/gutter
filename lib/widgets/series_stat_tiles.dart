// lib/widgets/series_stat_tiles.dart
import '../providers/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../config/app_theme.dart';
import '../config/comic_style.dart';
import '../config/reading_estimate.dart';
import '../config/scheme.dart';
import '../models/series.dart';
import 'cover_flight_route.dart';

/// "Continue"/"Up next" card sitting below the series header: cover thumb,
/// accent-mono label, issue name, a sub-line that agrees with the hero card
/// and the TO FINISH stat tile (all three derive from [kMinutesPerPage] via
/// [formatMinutesLeft] — never compute minutes independently here), and a
/// right-aligned accent pill that opens the reader.
///
/// Sits on the page background (below the header's backdrop fade), so —
/// unlike the header's scrim-locked text — every colour here follows the
/// active [Scheme]. See docs/superpowers/DEFERRED.md §"The scrim bug class".
class NextUpCard extends ConsumerWidget {
  final SeriesIssue issue;
  final Color accent;
  final String? coverImageUrl;
  final VoidCallback onTap;

  const NextUpCard({
    super.key,
    required this.issue,
    required this.accent,
    this.coverImageUrl,
    required this.onTap,
  });

  bool get _inProgress =>
      issue.status == 'in_progress' && issue.currentPage != null && issue.totalPages != null;

  String _subLine() {
    if (_inProgress) {
      final current = issue.currentPage!;
      final total = issue.totalPages!;
      final pagesLeft = (total - current - 1).clamp(0, total);
      final estimate = formatMinutesLeft(pagesLeft);
      final page = 'Page ${current + 1} of $total';
      return estimate.isEmpty ? page : '$page · $estimate';
    }
    // Page count unknown until the archive is first opened.
    if (issue.totalPages == null) return issue.status == 'unread' ? 'Not started' : 'In progress';
    final total = issue.totalPages!;
    final estimate = formatMinutesLeft(total);
    final pages = '$total ${total == 1 ? 'page' : 'pages'}';
    return estimate.isEmpty ? pages : '$pages · ~$estimate';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final comic = ComicTokens.watch(ref, context, accent);
    final ink = Scheme.onAccent(accent);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.scheme.s1,
          borderRadius: BorderRadius.circular(AppTheme.r20),
          border: Border.all(
            color: comic.hardShadow ? comic.ink : context.scheme.borderFaint,
            width: comic.hardShadow ? comic.borderWidth : 0.5,
          ),
          boxShadow: comic.hardShadow ? comic.cardShadow : null,
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppTheme.r8),
              child: SizedBox(
                width: 44,
                height: 64,
                child: coverImageUrl != null
                    ? CoverAnchor(
                        comicId: issue.id,
                        imageUrl: coverImageUrl!,
                        radius: AppTheme.r8,
                        child: CachedNetworkImage(imageUrl: coverImageUrl!, httpHeaders: imageHeadersOf(context, coverImageUrl!), fit: BoxFit.cover),
                      )
                    : Container(color: context.scheme.s2),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _inProgress ? 'CONTINUE' : 'UP NEXT',
                    style: context.monoCaption.copyWith(color: accent, fontSize: 11),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    issue.displayName,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: context.scheme.tx),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _subLine(),
                    style: TextStyle(fontSize: 12, color: context.scheme.t2),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(AppTheme.pill)),
              child: Center(
                child: Text(
                  _inProgress ? 'Resume' : 'Read',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: ink),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Row of `s1` stat tiles under the next-up card.
///
/// Only ships tiles backed by real per-series data:
/// - ISSUES: `SeriesDetail.readCount` / `.issueCount`.
/// - TO FINISH: remaining pages across unread/in-progress issues ×
///   [kMinutesPerPage], via [formatMinutesLeft] (agrees with the hero card
///   and [NextUpCard] — never compute minutes independently).
///
/// TIME READ and LAST READ are deliberately omitted, not fabricated:
/// - TIME READ has no per-series backend figure. `StatsSummary.timeReadS`
///   is app-wide; `StatsSummary`'s per-series breakdown (`SeriesPages`) is a
///   top-N list from `/stats/summary`, not a lookup by arbitrary series ID,
///   so showing it here would mean plumbing a new endpoint/provider — out of
///   scope per the design handoff (same call Task 2 made for status caption).
/// - LAST READ (`MirrorSeries.lastReadAt`) lives on `MirrorSeries`, not on
///   `SeriesDetail` (what this widget receives via `seriesDetailProvider`,
///   which streams `watchSeriesDetail` — a different mirror query). Reaching
///   it would mean plumbing new provider state, which the brief says to
///   avoid in favor of omitting.
class SeriesStatTiles extends StatelessWidget {
  final SeriesDetail detail;

  const SeriesStatTiles({super.key, required this.detail});

  int _remainingPages() {
    var pages = 0;
    for (final issue in detail.issues) {
      final total = issue.totalPages;
      if (total == null) continue;
      if (issue.status == 'unread') {
        pages += total;
      } else if (issue.status == 'in_progress') {
        final current = issue.currentPage ?? 0;
        pages += (total - current - 1).clamp(0, total);
      }
    }
    return pages;
  }

  @override
  Widget build(BuildContext context) {
    final toFinish = formatMinutesLeft(_remainingPages());
    final unfinished = detail.readCount < detail.issueCount;
    return Row(
      children: [
        Expanded(child: _Tile(label: 'ISSUES', value: '${detail.readCount}/${detail.issueCount}')),
        const SizedBox(width: 10),
        // `formatMinutesLeft` returns empty at zero precisely to avoid
        // "0 min left"; a finished series reads "Done", not a zero countdown.
        Expanded(child: _Tile(label: 'TO FINISH', value: toFinish.isNotEmpty ? toFinish : unfinished ? '—' : 'Done')),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  final String label;
  final String value;

  const _Tile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: context.scheme.s1,
        borderRadius: BorderRadius.circular(AppTheme.r14),
        border: Border.all(color: context.scheme.borderFaint, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: context.monoCaption.copyWith(fontSize: 10)),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: context.scheme.tx),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
