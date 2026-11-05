import 'package:flutter/material.dart';
import '../config/app_theme.dart';

class AmbientProgressRail extends StatelessWidget {
  final double progress;
  final int totalPages;
  final List<int> bookmarkPages;
  final Color accent;

  const AmbientProgressRail({
    super.key,
    required this.progress,
    required this.totalPages,
    this.bookmarkPages = const [],
    this.accent = AppTheme.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      height: 2,
      child: CustomPaint(
        painter: _RailPainter(
          progress: progress.clamp(0.0, 1.0),
          totalPages: totalPages,
          bookmarkPages: bookmarkPages,
          accent: accent,
        ),
      ),
    );
  }
}

class _RailPainter extends CustomPainter {
  final double progress;
  final int totalPages;
  final List<int> bookmarkPages;
  final Color accent;

  _RailPainter({required this.progress, required this.totalPages, required this.bookmarkPages, required this.accent});

  @override
  void paint(Canvas canvas, Size size) {
    final trackPaint = Paint()..color = Colors.white.withValues(alpha: 0.08);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), trackPaint);

    final fillWidth = size.width * progress;
    if (fillWidth > 0) {
      final fillPaint = Paint()
        ..shader = LinearGradient(colors: [accent.withValues(alpha: 0.6), accent])
            .createShader(Rect.fromLTWH(0, 0, fillWidth, size.height));
      canvas.drawRect(Rect.fromLTWH(0, 0, fillWidth, size.height), fillPaint);

      final glowPaint = Paint()
        ..color = accent.withValues(alpha: 0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
      canvas.drawRect(Rect.fromLTWH(0, -2, fillWidth, size.height + 4), glowPaint);
    }

    if (totalPages > 1) {
      for (final page in bookmarkPages) {
        final x = (page / (totalPages - 1)) * size.width;
        canvas.drawCircle(Offset(x, size.height / 2), 2, Paint()..color = AppTheme.amber);
        canvas.drawCircle(Offset(x, size.height / 2), 2, Paint()..color = AppTheme.amber.withValues(alpha: 0.4)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
      }
    }
  }

  @override
  bool shouldRepaint(_RailPainter old) => old.progress != progress || old.bookmarkPages != bookmarkPages || old.accent != accent;
}
