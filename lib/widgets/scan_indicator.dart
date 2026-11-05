// lib/widgets/scan_indicator.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/app_theme.dart';
import '../config/scheme.dart';
import '../providers/accent_provider.dart';
import '../providers/scan_provider.dart';
import '../providers/scan_state.dart';

/// A compact, app-wide progress chip shown only while a chapter scan runs.
class ScanIndicator extends ConsumerWidget {
  const ScanIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scan = ref.watch(scanProvider);
    if (scan.phase != ScanPhase.running) return const SizedBox.shrink();

    final pct = (scan.progress * 100).round();
    final label = scan.total > 0
        ? 'Scanning ${scan.title ?? ''} — ${scan.scanned}/${scan.total} ($pct%)'
        : 'Scanning ${scan.title ?? ''}…';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: context.scheme.s1,
        borderRadius: BorderRadius.circular(AppTheme.r12),
        border: Border.all(color: context.scheme.hair),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: context.scheme.tx, fontSize: 12),
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.r4),
            child: LinearProgressIndicator(
              value: scan.total > 0 ? scan.progress : null,
              minHeight: 4,
              backgroundColor: context.scheme.s2,
              valueColor: AlwaysStoppedAnimation(
                ref.watch(accentProvider).value ?? AppTheme.accent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
