import 'package:flutter/material.dart';
import '../config/layout_breakpoint.dart';
import '../config/scheme.dart';
import '../models/stats_summary.dart';

class CalendarHeatmap extends StatelessWidget {
  final List<DailyPages> pagesPerDay;
  final Color accent;

  const CalendarHeatmap({
    super.key,
    required this.pagesPerDay,
    required this.accent,
  });

  /// Returns the intensity bucket index (0..4) for a given page count.
  /// Buckets: 0, 1-5, 6-15, 16-40, 41+.
  static int bucketIndex(int pages) {
    if (pages == 0) return 0;
    if (pages <= 5) return 1;
    if (pages <= 15) return 2;
    if (pages <= 40) return 3;
    return 4;
  }

  @override
  Widget build(BuildContext context) {
    final isTablet = LayoutBreakpoint.isTablet(context);
    final cellSize = isTablet ? 12.0 : 9.0;
    const gap = 1.0;
    const rows = 7;
    const cols = 53;
    final width = cols * (cellSize + gap) - gap;
    final height = rows * (cellSize + gap) - gap;

    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        painter: _HeatmapPainter(
          pagesPerDay: pagesPerDay,
          accent: accent,
          cellSize: cellSize,
          gap: gap,
          emptyColor: context.scheme.s2,
        ),
      ),
    );
  }
}

class _HeatmapPainter extends CustomPainter {
  final List<DailyPages> pagesPerDay;
  final Color accent;
  final double cellSize;
  final double gap;
  final Color emptyColor;

  _HeatmapPainter({
    required this.pagesPerDay,
    required this.accent,
    required this.cellSize,
    required this.gap,
    required this.emptyColor,
  });

  static const _bucketAlphas = [0.0, 0.25, 0.5, 0.75, 1.0];

  @override
  void paint(Canvas canvas, Size size) {
    if (pagesPerDay.isEmpty) return;

    // Render the last 365 entries column-major: column = i ~/ 7, row = i % 7.
    // Rows are NOT day-of-week-aligned (deferred polish per spec).
    final entries = pagesPerDay.length > 365
        ? pagesPerDay.sublist(pagesPerDay.length - 365)
        : pagesPerDay;

    for (var i = 0; i < entries.length; i++) {
      final col = i ~/ 7;
      final row = i % 7;
      final x = col * (cellSize + gap);
      final y = row * (cellSize + gap);
      final pages = entries[i].pages;
      final bucket = CalendarHeatmap.bucketIndex(pages);
      final color = bucket == 0
          ? emptyColor
          : accent.withValues(alpha: _bucketAlphas[bucket]);
      final rect = Rect.fromLTWH(x, y, cellSize, cellSize);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(2)),
        Paint()..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_HeatmapPainter old) =>
      old.pagesPerDay != pagesPerDay ||
      old.accent != accent ||
      old.cellSize != cellSize ||
      old.emptyColor != emptyColor;
}
