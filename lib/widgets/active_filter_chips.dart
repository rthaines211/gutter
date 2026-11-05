import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/app_theme.dart';
import '../models/library_filter.dart';
import '../providers/library_provider.dart';

class ActiveFilterChips extends ConsumerWidget {
  final Color accent;

  const ActiveFilterChips({super.key, this.accent = AppTheme.accent});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(libraryFilterProvider);

    if (filter.activeFilterCount == 0) return const SizedBox.shrink();

    final notifier = ref.read(libraryFilterProvider.notifier);
    final chips = _buildChipData(filter, notifier);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Row(
        children: [
          ...chips,
          if (chips.length >= 2)
            _FilterChip(
              label: 'Clear all',
              isClearAll: true,
              accent: accent,
              onDismiss: () {
                HapticFeedback.selectionClick();
                notifier.clearMetadataFilters();
              },
            ),
        ],
      ),
    );
  }

  List<Widget> _buildChipData(
    LibraryFilter filter,
    LibraryFilterNotifier notifier,
  ) {
    final chips = <Widget>[];

    if (filter.publisher != null) {
      chips.add(_FilterChip(
        label: 'Publisher: ${filter.publisher}',
        accent: accent,
        onDismiss: () {
          HapticFeedback.selectionClick();
          notifier.setPublisher(null);
        },
      ));
    }

    if (filter.genre != null) {
      chips.add(_FilterChip(
        label: 'Genre: ${filter.genre}',
        accent: accent,
        onDismiss: () {
          HapticFeedback.selectionClick();
          notifier.setGenre(null);
        },
      ));
    }

    if (filter.writer != null) {
      chips.add(_FilterChip(
        label: 'Writer: ${filter.writer}',
        accent: accent,
        onDismiss: () {
          HapticFeedback.selectionClick();
          notifier.setWriter(null);
        },
      ));
    }

    if (filter.penciller != null) {
      chips.add(_FilterChip(
        label: 'Penciller: ${filter.penciller}',
        accent: accent,
        onDismiss: () {
          HapticFeedback.selectionClick();
          notifier.setPenciller(null);
        },
      ));
    }

    if (filter.yearMin != null) {
      chips.add(_FilterChip(
        label: 'Year ≥ ${filter.yearMin}',
        accent: accent,
        onDismiss: () {
          HapticFeedback.selectionClick();
          notifier.setYearRange(null, filter.yearMax);
        },
      ));
    }

    if (filter.yearMax != null) {
      chips.add(_FilterChip(
        label: 'Year ≤ ${filter.yearMax}',
        accent: accent,
        onDismiss: () {
          HapticFeedback.selectionClick();
          notifier.setYearRange(filter.yearMin, null);
        },
      ));
    }

    return chips;
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.onDismiss,
    this.isClearAll = false,
    this.accent = AppTheme.accent,
  });

  final String label;
  final VoidCallback onDismiss;
  final bool isClearAll;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: isClearAll ? onDismiss : null,
        child: Container(
          height: 30,
          padding: EdgeInsets.only(
            left: 10,
            right: isClearAll ? 10 : 4,
          ),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: accent.withValues(alpha: 0.3),
              width: 0.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: accent,
                ),
              ),
              if (!isClearAll) ...[
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: onDismiss,
                  child: Icon(
                    Icons.close,
                    size: 14,
                    color: accent,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
