// lib/widgets/library_mode_pill.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/scheme.dart';
import '../providers/library_mode_provider.dart';

/// Header pill that cycles the library grouping: Sectioned A–Z → By publisher →
/// Flat grid. Handoff spec: `s1` pill, 32h, icon + label, tap cycles.
class LibraryModePill extends ConsumerWidget {
  const LibraryModePill({super.key});

  static const _labels = {
    LibraryMode.sectioned: 'Sectioned A–Z',
    LibraryMode.publisher: 'By publisher',
    LibraryMode.flat: 'Flat grid',
  };

  static const _icons = {
    LibraryMode.sectioned: Icons.sort_by_alpha_rounded,
    LibraryMode.publisher: Icons.business_rounded,
    LibraryMode.flat: Icons.grid_view_rounded,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(libraryModeProvider);
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        ref.read(libraryModeProvider.notifier).cycle();
      },
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: context.scheme.s1,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.scheme.hair, width: 0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_icons[mode], size: 13, color: context.scheme.t2),
            const SizedBox(width: 6),
            Text(
              _labels[mode]!,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: context.scheme.t2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
