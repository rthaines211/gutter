import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../config/app_theme.dart';
import '../config/layout_breakpoint.dart';
import '../config/scheme.dart';
import '../models/stats_summary.dart';
import '../providers/providers.dart';
import '../screens/series_detail_screen.dart';
import 'calendar_heatmap.dart';
import 'reading_stamp.dart';

class StatsDashboard extends ConsumerWidget {
  final StatsSummary summary;
  final Color accent;
  const StatsDashboard({super.key, required this.summary, this.accent = AppTheme.accent});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final serverUrl = ref.watch(serverConfigProvider).serverUrl;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 260),
              child: ReadingStamp(
                summary: summary,
                accent: accent,
                month: DateTime.now(),
              ),
            ),
          ),
          const SizedBox(height: 24),
          _buildSummaryCards(context),
          const SizedBox(height: 16),
          _buildHabitCards(context),
          const SizedBox(height: 32),
          Text('ACTIVITY (LAST YEAR)', style: context.sectionHeader),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: CalendarHeatmap(
              pagesPerDay: summary.pagesPerDay,
              accent: accent,
            ),
          ),
          const SizedBox(height: 32),
          _buildHourOfDayChart(context),
          const SizedBox(height: 32),
          _buildPagesPerDayChart(context),
          const SizedBox(height: 32),
          _buildBreakdownSection(
            context,
            title: 'TOP GENRES',
            items: summary.topGenres,
            emptyMessage: 'Read comics with metadata to see genres',
          ),
          const SizedBox(height: 32),
          _buildBreakdownSection(
            context,
            title: 'TOP PUBLISHERS',
            items: summary.topPublishers,
            emptyMessage: 'Read comics with metadata to see publishers',
          ),
          const SizedBox(height: 32),
          _buildTopSeriesSection(context, serverUrl),
          const SizedBox(height: 32),
          _buildBreakdownSection(
            context,
            title: 'TOP WRITERS',
            items: summary.topWriters,
            emptyMessage: 'Read comics with metadata to see writers',
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSummaryCards(BuildContext context) {
    final cards = [
      _StatCard(
        label: 'Pages Read',
        value: _formatNumber(summary.allTime.pagesRead),
        subtitle: 'this week: ${_formatNumber(summary.thisWeek.pagesRead)}',
        accent: accent,
      ),
      _StatCard(
        label: 'Issues Finished',
        value: _formatNumber(summary.allTime.issuesFinished),
        accent: accent,
      ),
      _StatCard(
        label: 'Series Completed',
        value: _formatNumber(summary.allTime.seriesCompleted),
        accent: accent,
      ),
      _StatCard(
        label: 'Time Read',
        value: summary.allTime.formattedTime,
        subtitle: 'this week: ${summary.thisWeek.formattedTime}',
        accent: accent,
      ),
    ];

    if (LayoutBreakpoint.isTablet(context)) {
      return Column(
        children: [
          Row(
            children: [
              Expanded(child: cards[0]),
              const SizedBox(width: 12),
              Expanded(child: cards[1]),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: cards[2]),
              const SizedBox(width: 12),
              Expanded(child: cards[3]),
            ],
          ),
        ],
      );
    }

    return SizedBox(
      height: 100,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: cards.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (_, i) => SizedBox(width: 160, child: cards[i]),
      ),
    );
  }

  Widget _buildHabitCards(BuildContext context) {
    final streak = summary.streak;
    final avgMin = (summary.avgSessionS / 60).round();
    final compl = summary.completionRate;

    final cards = [
      _StatCard(
        label: 'Current Streak',
        value: '${streak.current}d',
        subtitle: 'longest: ${streak.longest}d',
        accent: accent,
      ),
      _StatCard(
        label: 'Avg Session',
        value: avgMin == 0 ? '—' : '${avgMin}m',
        accent: accent,
      ),
      _StatCard(
        label: 'Completion',
        value: compl.started == 0 ? '—' : '${compl.ratePercent}%',
        subtitle: compl.started == 0
            ? null
            : '${compl.completed} of ${compl.started} series',
        accent: accent,
      ),
    ];

    if (LayoutBreakpoint.isTablet(context)) {
      return Row(
        children: [
          Expanded(child: cards[0]),
          const SizedBox(width: 12),
          Expanded(child: cards[1]),
          const SizedBox(width: 12),
          Expanded(child: cards[2]),
        ],
      );
    }

    return SizedBox(
      height: 100,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: cards.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (_, i) => SizedBox(width: 160, child: cards[i]),
      ),
    );
  }

  Widget _buildHourOfDayChart(BuildContext context) {
    final data = summary.hourHistogram;
    final allZeroes = data.isEmpty || data.every((d) => d.pages == 0);
    final scheme = context.scheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('READING BY HOUR', style: context.sectionHeader),
        const SizedBox(height: 16),
        if (allZeroes)
          _buildEmptyPlaceholder(context, 'Start reading to see your daily pattern')
        else
          SizedBox(
            height: 160,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    tooltipRoundedRadius: 8,
                    getTooltipColor: (_) => scheme.s3,
                    getTooltipItem: (group, _, _, _) {
                      final h = group.x.toInt();
                      final pages = data[h].pages;
                      return BarTooltipItem(
                        '${_formatHour(h)}\n$pages pages',
                        TextStyle(
                          color: scheme.tx,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 36,
                      getTitlesWidget: (value, meta) {
                        if (value == meta.max || value == meta.min) {
                          return const SizedBox.shrink();
                        }
                        return Text(value.toInt().toString(),
                            style: context.monoCaption);
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      getTitlesWidget: (value, _) {
                        final h = value.toInt();
                        if (h % 6 != 0) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(_formatHour(h), style: context.monoCaption),
                        );
                      },
                    ),
                  ),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) =>
                      FlLine(color: scheme.hair, strokeWidth: 1),
                ),
                borderData: FlBorderData(show: false),
                barGroups: List.generate(data.length, (i) {
                  return BarChartGroupData(
                    x: data[i].hour,
                    barRods: [
                      BarChartRodData(
                        toY: data[i].pages.toDouble(),
                        color: accent,
                        width: 8,
                        borderRadius:
                            const BorderRadius.vertical(top: Radius.circular(3)),
                      ),
                    ],
                  );
                }),
              ),
            ),
          ),
      ],
    );
  }

  String _formatHour(int h) {
    if (h == 0) return '12a';
    if (h < 12) return '${h}a';
    if (h == 12) return '12p';
    return '${h - 12}p';
  }

  Widget _buildTopSeriesSection(BuildContext context, String serverUrl) {
    final items = summary.topSeries;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('TOP SERIES', style: context.sectionHeader),
        const SizedBox(height: 12),
        if (items.isEmpty)
          _buildEmptyPlaceholder(context, 'Start reading to see your top series')
        else
          ...List.generate(items.length, (i) {
            final item = items[i];
            final maxPages = items.first.pages;
            final fraction = maxPages > 0 ? item.pages / maxPages : 0.0;
            final opacity = 1.0 - (i * 0.15).clamp(0.0, 0.6);
            final coverUrl = item.coverUrl.isNotEmpty
                ? '$serverUrl${item.coverUrl}'
                : null;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: InkWell(
                onTap: () {
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => SeriesDetailScreen(seriesId: item.seriesId),
                    settings: const RouteSettings(name: '/series-detail'),
                  ));
                },
                borderRadius: BorderRadius.circular(AppTheme.r8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: SizedBox(
                        width: 32,
                        height: 48,
                        child: coverUrl == null
                            ? Container(color: context.scheme.s2)
                            : CachedNetworkImage(
                                imageUrl: coverUrl,
                                fit: BoxFit.cover,
                                placeholder: (_, _) =>
                                    Container(color: context.scheme.s2),
                                errorWidget: (_, _, _) =>
                                    Container(color: context.scheme.s2),
                              ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  item.name,
                                  style: TextStyle(
                                    color: context.scheme.t2,
                                    fontSize: 14,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text(
                                '${item.pages}p',
                                style: context.monoLabel,
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              return Container(
                                height: 8,
                                width: constraints.maxWidth * fraction,
                                decoration: BoxDecoration(
                                  color: accent.withValues(alpha: opacity),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildPagesPerDayChart(BuildContext context) {
    final allData = summary.pagesPerDay;
    final data = allData.length > 30
        ? allData.sublist(allData.length - 30)
        : allData;
    final allZeroes = data.isEmpty || data.every((d) => d.pages == 0);
    final scheme = context.scheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('PAGES PER DAY', style: context.sectionHeader),
        const SizedBox(height: 16),
        if (allZeroes)
          _buildEmptyPlaceholder(context, 'Start reading to see your chart')
        else
          SizedBox(
            height: 200,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    tooltipRoundedRadius: 8,
                    getTooltipColor: (_) => scheme.s3,
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final entry = data[group.x.toInt()];
                      return BarTooltipItem(
                        '${entry.date}\n${entry.pages} pages',
                        TextStyle(
                          color: scheme.tx,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      getTitlesWidget: (value, meta) {
                        if (value == meta.max || value == meta.min) {
                          return const SizedBox.shrink();
                        }
                        return Text(
                          value.toInt().toString(),
                          style: context.monoCaption,
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index < 0 || index >= data.length) {
                          return const SizedBox.shrink();
                        }
                        if (index % 7 != 0) return const SizedBox.shrink();
                        final date = data[index].date;
                        final label = date.length >= 5
                            ? date.substring(date.length - 5)
                            : date;
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(label, style: context.monoCaption),
                        );
                      },
                    ),
                  ),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: scheme.hair,
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                barGroups: List.generate(data.length, (i) {
                  return BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: data[i].pages.toDouble(),
                        color: accent,
                        width: data.length > 14 ? 6 : 10,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(3),
                        ),
                      ),
                    ],
                  );
                }),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildBreakdownSection(
    BuildContext context, {
    required String title,
    required List<NameCount> items,
    required String emptyMessage,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: context.sectionHeader),
        const SizedBox(height: 12),
        if (items.isEmpty)
          _buildEmptyPlaceholder(context, emptyMessage)
        else
          ...List.generate(items.length, (i) {
            final item = items[i];
            final maxCount = items.first.count;
            final fraction = maxCount > 0 ? item.count / maxCount : 0.0;
            final opacity = 1.0 - (i * 0.15).clamp(0.0, 0.6);
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          item.name,
                          style: TextStyle(
                            color: context.scheme.t2,
                            fontSize: 14,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        item.count.toString(),
                        style: context.monoLabel,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      return Container(
                        height: 8,
                        width: constraints.maxWidth * fraction,
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: opacity),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      );
                    },
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  Widget _buildEmptyPlaceholder(BuildContext context, String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40),
      decoration: BoxDecoration(
        color: context.scheme.s2,
        borderRadius: BorderRadius.circular(AppTheme.r12),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: context.scheme.t3,
          fontSize: 14,
        ),
      ),
    );
  }

  String _formatNumber(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toString();
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final String? subtitle;
  final Color accent;

  const _StatCard({
    required this.label,
    required this.value,
    this.subtitle,
    this.accent = AppTheme.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.scheme.s2,
        borderRadius: BorderRadius.circular(AppTheme.r12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            style: context.monoCaption,
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: accent,
              height: 1.1,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: TextStyle(
                color: context.scheme.t3,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
