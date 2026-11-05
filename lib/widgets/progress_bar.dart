import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../config/scheme.dart';

class ProgressBar extends StatelessWidget {
  final double value;
  final double height;
  final Color? color;
  final Color? trackColor;

  const ProgressBar({
    super.key,
    required this.value,
    this.height = 3,
    this.color,
    this.trackColor,
  });

  @override
  Widget build(BuildContext context) {
    final fillColor = color ?? AppTheme.accent;
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: trackColor ?? context.scheme.hair,
        borderRadius: BorderRadius.circular(AppTheme.pill),
      ),
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: value.clamp(0.0, 1.0)),
        duration: const Duration(milliseconds: 600),
        curve: const Cubic(0.2, 0.8, 0.2, 1),
        builder: (context, animValue, _) {
          return FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: animValue,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [fillColor, fillColor.withValues(alpha: 0.73)],
                ),
                borderRadius: BorderRadius.circular(AppTheme.pill),
                boxShadow: [
                  BoxShadow(
                    color: fillColor.withValues(alpha: 0.4),
                    blurRadius: 8,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
