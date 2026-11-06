import 'dart:math';
import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../config/comic_style.dart';
import '../config/scheme.dart';
import '../models/stats_summary.dart';

/// "THIS WEEK" activity card for the Read tab: a total-pages figure plus 7
/// mini bars for the last 7 days. Sits on the page background (not artwork)
/// so it uses `context.scheme` colours throughout, unlike the hero card's
/// pinned-light scrim text.
///
/// Always renders exactly 7 bars: the last 7 entries of [pagesPerDay] are
/// used, left-padded with zero-page days if fewer than 7 are given. Today
/// and the best (highest-pages) day render solid [accent]; other days with
/// activity render `accent` at 55% opacity; zero-page days render
/// `scheme.s3`.
class ThisWeekCard extends StatelessWidget {
  final List<DailyPages> pagesPerDay;
  final ComicTokens comic;
  final Color accent;

  const ThisWeekCard({
    super.key,
    required this.pagesPerDay,
    required this.comic,
    required this.accent,
  });

  /// Last 7 entries of [pagesPerDay], padded at the front with zero-page
  /// days if there are fewer than 7. Dates for padding are back-filled from
  /// the earliest real entry (or today, if the list is empty) so the padded
  /// days never collide with "today".
  static List<DailyPages> _lastSevenPadded(List<DailyPages> pagesPerDay) {
    final last7 = pagesPerDay.length > 7
        ? pagesPerDay.sublist(pagesPerDay.length - 7)
        : pagesPerDay;
    if (last7.length == 7) return last7;

    final missing = 7 - last7.length;
    final anchor = last7.isNotEmpty
        ? (DateTime.tryParse(last7.first.date) ?? DateTime.now())
        : DateTime.now().add(const Duration(days: 1));
    final padding = List.generate(missing, (i) {
      final date = anchor.subtract(Duration(days: missing - i));
      return DailyPages(date: _fmt(date), pages: 0);
    });
    return [...padding, ...last7];
  }

  static String _fmt(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Same convention as `StatsStrip._computeStreak`: parse the date string
  /// with `DateTime.tryParse` and compare day-difference to `DateTime.now()`.
  static bool _isToday(DailyPages entry) {
    final date = DateTime.tryParse(entry.date);
    if (date == null) return false;
    final now = DateTime.now();
    return now.difference(date).inDays == 0;
  }

  @override
  Widget build(BuildContext context) {
    final week = _lastSevenPadded(pagesPerDay);
    final totalPages = week.fold<int>(0, (sum, d) => sum + d.pages);
    final maxPages = week.fold<int>(0, (m, d) => max(m, d.pages));
    final bestIndex =
        maxPages > 0 ? week.indexWhere((d) => d.pages == maxPages) : -1;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.scheme.s1,
          borderRadius: BorderRadius.circular(AppTheme.r18),
          border: Border.all(color: context.scheme.borderFaint, width: 0.5),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('THIS WEEK',
                      style: AppTheme.monoLabel.copyWith(
                        fontSize: 11,
                        color: context.scheme.t3,
                      )),
                  const SizedBox(height: 4),
                  Text('$totalPages ${totalPages == 1 ? 'page' : 'pages'}',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        color: context.scheme.tx,
                      )),
                  const SizedBox(height: 2),
                  Text(
                    'across the last 7 days',
                    style: context.monoCaption.copyWith(fontSize: 11),
                  ),
                ],
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(week.length, (i) {
                final entry = week[i];
                final isToday = _isToday(entry);
                final isBest = i == bestIndex;
                final Color color;
                if (entry.pages <= 0) {
                  color = context.scheme.s3;
                } else if (isToday || isBest) {
                  color = accent;
                } else {
                  color = accent.withValues(alpha: 0.55);
                }
                final fraction =
                    maxPages > 0 ? entry.pages / maxPages : 0.0;
                final height = 6.0 + fraction * 26.0;
                return Padding(
                  padding: EdgeInsets.only(left: i == 0 ? 0 : 4),
                  child: Container(
                    key: const ValueKey('this_week_bar'),
                    width: 10,
                    height: height,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}
