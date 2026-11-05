import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../config/comic_style.dart';
import '../config/scheme.dart';

/// Reading-streak pill for the Read tab header: `s1` fill, ink border, an
/// amber flame, the day count, then the literal label "DAY STREAK" (used
/// unchanged at any count, same as a stat label like "3 DAY FORECAST").
///
/// Renders nothing at `days == 0` — a "0 DAY STREAK" chip is worse than no
/// chip, so callers can place this unconditionally in a Row without an
/// `if (streak > 0)` guard at every call site.
class StreakChip extends StatelessWidget {
  final int days;
  final ComicTokens comic;

  const StreakChip({
    super.key,
    required this.days,
    required this.comic,
  });

  @override
  Widget build(BuildContext context) {
    if (days <= 0) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: context.scheme.s1,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: comic.ink, width: comic.borderWidth),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.local_fire_department, size: 14, color: AppTheme.amber),
          const SizedBox(width: 4),
          Text(
            '$days',
            style: AppTheme.monoLabel.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 4),
          const Text('DAY STREAK', style: AppTheme.monoCaption),
        ],
      ),
    );
  }
}
