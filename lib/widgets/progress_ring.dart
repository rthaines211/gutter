import 'dart:math';
import 'package:flutter/material.dart';
import '../config/app_theme.dart';

class ProgressRing extends StatelessWidget {
  final double value;
  final double size;
  final double strokeWidth;
  final Color? color;
  final Color? trackColor;

  const ProgressRing({
    super.key,
    required this.value,
    this.size = 28,
    this.strokeWidth = 3,
    this.color,
    this.trackColor,
  });

  @override
  Widget build(BuildContext context) {
    final ringColor = color ?? AppTheme.accent;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: ringColor.withValues(alpha: 0.25),
            blurRadius: 8,
          ),
        ],
      ),
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: value.clamp(0.0, 1.0)),
        duration: const Duration(milliseconds: 600),
        curve: const Cubic(0.2, 0.8, 0.2, 1),
        builder: (context, animValue, _) {
          return CustomPaint(
            painter: _RingPainter(
              value: animValue,
              strokeWidth: strokeWidth,
              color: ringColor,
              trackColor: trackColor ?? Colors.white.withValues(alpha: 0.12),
            ),
          );
        },
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double value;
  final double strokeWidth;
  final Color color;
  final Color trackColor;

  _RingPainter({
    required this.value,
    required this.strokeWidth,
    required this.color,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, trackPaint);

    final valuePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi / 2,
      2 * pi * value,
      false,
      valuePaint,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value || old.color != color;
}
