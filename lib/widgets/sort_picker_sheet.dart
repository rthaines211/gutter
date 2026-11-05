import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/app_theme.dart';
import '../config/scheme.dart';
import '../providers/grid_density_provider.dart';
import '../providers/library_provider.dart';

class SortPickerSheet extends ConsumerWidget {
  final Color accent;

  const SortPickerSheet({super.key, this.accent = AppTheme.accent});

  static const _sortOptions = [
    _SortOption(key: 'name', label: 'Name'),
    _SortOption(key: 'recent', label: 'Recently Added'),
    _SortOption(key: 'recently_read', label: 'Recently Read'),
    _SortOption(key: 'publisher', label: 'Publisher'),
    _SortOption(key: 'year', label: 'Year'),
    _SortOption(key: 'issue_count', label: 'Issue Count'),
    _SortOption(key: 'unread_count', label: 'Unread Count'),
    _SortOption(key: 'progress', label: 'Progress'),
  ];

  static const _descDefaultSorts = {
    'recent',
    'recently_read',
    'unread_count',
    'progress',
  };

  String _defaultOrderFor(String sortKey) {
    return _descDefaultSorts.contains(sortKey) ? 'desc' : 'asc';
  }

  void _handleTap(BuildContext context, WidgetRef ref, String sortKey) {
    HapticFeedback.selectionClick();
    final notifier = ref.read(libraryFilterProvider.notifier);
    final filter = ref.read(libraryFilterProvider);
    if (sortKey == filter.sort) {
      notifier.setOrder(filter.order == 'asc' ? 'desc' : 'asc');
    } else {
      notifier.setSort(sortKey);
      notifier.setOrder(_defaultOrderFor(sortKey));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(libraryFilterProvider);
    final currentSort = filter.sort;
    final currentOrder = filter.order;
    // Sectioning is derived from the sort, not a separate setting — a second
    // toggle would be a second source of truth for the same thing, and the
    // two could disagree. The caption below states the relationship instead.
    final sectioned = filter.sort == 'name' && filter.order == 'asc';
    return Container(
      decoration: BoxDecoration(
        color: context.scheme.s1,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppTheme.r16),
        ),
      ),
      child: SafeArea(
        top: false,
        // Scrollable: the sheet now carries a density picker above eight sort
        // rows, which overflows a short viewport (a small phone in landscape,
        // or a large text scale).
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              // Grabber handle
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: context.scheme.t4,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              // Sheet title
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('View', style: AppTheme.titleMedium),
                ),
              ),
              const SizedBox(height: 12),
              _DensityRow(accent: accent),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    sectioned
                        ? 'Grouped A–Z. Sort by Name (A–Z) to keep the index.'
                        : 'Flat grid. Sort by Name ascending to group A–Z.',
                    style: context.monoCaption,
                  ),
                ),
              ),
              Divider(height: 1, thickness: 0.5, color: context.scheme.hair),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Sort By', style: AppTheme.titleMedium),
                ),
              ),
              const SizedBox(height: 8),
              // Sort options list
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _sortOptions.length,
                itemBuilder: (context, index) {
                  final option = _sortOptions[index];
                  final isActive = option.key == currentSort;
                  return _SortRow(
                    option: option,
                    isActive: isActive,
                    order: isActive ? currentOrder : null,
                    accent: accent,
                    onTap: () => _handleTap(context, ref, option.key),
                  );
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _SortOption {
  final String key;
  final String label;

  const _SortOption({required this.key, required this.label});
}

class _SortRow extends StatelessWidget {
  final _SortOption option;
  final bool isActive;
  final String? order;
  final VoidCallback onTap;
  final Color accent;

  const _SortRow({
    required this.option,
    required this.isActive,
    required this.order,
    required this.onTap,
    this.accent = AppTheme.accent,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Text(
                option.label,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                  color: isActive ? accent : context.scheme.tx,
                ),
              ),
            ),
            if (isActive && order != null)
              Icon(
                order == 'asc'
                    ? Icons.arrow_upward_rounded
                    : Icons.arrow_downward_rounded,
                size: 18,
                color: accent,
              ),
          ],
        ),
      ),
    );
  }
}

/// 2 / 3 / 4 column picker. Density drives tile typography; the actual column
/// count is derived from it and the viewport width.
class _DensityRow extends ConsumerWidget {
  final Color accent;

  const _DensityRow({required this.accent});

  static const _options = [
    (2, Icons.grid_view_rounded, 'Large'),
    (3, Icons.apps_rounded, 'Medium'),
    (4, Icons.grid_on_rounded, 'Small'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final density = ref.watch(gridDensityProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: _options.map((o) {
          final (value, icon, label) = o;
          final active = value == density;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  ref.read(gridDensityProvider.notifier).select(value);
                },
                child: Container(
                  height: 52,
                  decoration: BoxDecoration(
                    color: active
                        ? accent.withValues(alpha: 0.16)
                        : context.scheme.s2,
                    borderRadius: BorderRadius.circular(AppTheme.r12),
                    border: Border.all(
                      color: active ? accent : context.scheme.hair,
                      width: active ? 1.5 : 0.5,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        icon,
                        size: 18,
                        color: active ? accent : context.scheme.t2,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: active ? accent : context.scheme.t2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
