import 'dart:math';
import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../config/scheme.dart';
import '../models/stats_summary.dart';

class StatsStrip extends StatelessWidget {
  final StatsSummary stats;

  const StatsStrip({super.key, required this.stats});

  @override
  Widget build(BuildContext context) {
    final weekPages = stats.thisWeek.pagesRead;
    final weekSessions = stats.thisWeek.issuesFinished;
    final streak = _computeStreak(stats.pagesPerDay);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.scheme.s1,
          borderRadius: BorderRadius.circular(AppTheme.r18),
          border: Border.all(
            color: context.scheme.borderFaint,
            width: 0.5,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppTheme.amber,
                    AppTheme.amber.withValues(alpha: 0.7),
                  ],
                ),
                borderRadius: BorderRadius.circular(AppTheme.r12),
              ),
              child: Icon(Icons.local_fire_department_rounded,
                  size: 22, color: Scheme.onAccent(AppTheme.amber)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('$streak',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          )),
                      Text(streak == 1 ? ' day streak' : ' day streak',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: context.scheme.t2,
                          )),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$weekPages ${weekPages == 1 ? 'page' : 'pages'} · $weekSessions ${weekSessions == 1 ? 'issue' : 'issues'} this week',
                    style: context.monoCaption.copyWith(fontSize: 11),
                  ),
                ],
              ),
            ),
            _MiniBarChart(dailyPages: stats.pagesPerDay),
          ],
        ),
      ),
    );
  }

  static int _computeStreak(List<DailyPages> pagesPerDay) {
    if (pagesPerDay.isEmpty) return 0;
    int streak = 0;
    final now = DateTime.now();
    for (int i = pagesPerDay.length - 1; i >= 0; i--) {
      final entry = pagesPerDay[i];
      final date = DateTime.tryParse(entry.date);
      if (date == null) continue;
      final daysAgo = now.difference(date).inDays;
      if (daysAgo == streak && entry.pages > 0) {
        streak++;
      } else {
        break;
      }
    }
    return streak;
  }
}

class _MiniBarChart extends StatelessWidget {
  final List<DailyPages> dailyPages;

  const _MiniBarChart({required this.dailyPages});

  @override
  Widget build(BuildContext context) {
    final bars = dailyPages.length > 7
        ? dailyPages.sublist(dailyPages.length - 7)
        : dailyPages;
    if (bars.isEmpty) return const SizedBox(width: 56);
    final maxPages = bars.map((d) => d.pages).reduce(max).clamp(1, 99999);

    return SizedBox(
      width: 56,
      height: 28,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(7, (i) {
          final pages = i < bars.length ? bars[i].pages : 0;
          final fraction = pages / maxPages;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: Container(
                height: max(2.0, fraction * 28),
                decoration: BoxDecoration(
                  color: pages > 0
                      ? AppTheme.accent.withValues(alpha: 0.7)
                      : context.scheme.hair,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
