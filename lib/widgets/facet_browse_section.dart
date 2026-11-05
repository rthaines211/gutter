import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/app_theme.dart';
import '../config/scheme.dart';
import '../models/library_filter.dart';
import '../providers/facet_provider.dart';
import '../providers/library_provider.dart';

/// A sliver widget that renders expandable facet browse categories.
/// Used inside a CustomScrollView alongside other slivers.
class FacetBrowseSection extends ConsumerStatefulWidget {
  final Color accent;

  const FacetBrowseSection({super.key, this.accent = AppTheme.accent});

  @override
  ConsumerState<FacetBrowseSection> createState() => _FacetBrowseSectionState();
}

class _FacetBrowseSectionState extends ConsumerState<FacetBrowseSection> {
  String? _expandedFacet;

  static const _categories = [
    _FacetCategory(key: 'publisher', label: 'Publisher', icon: Icons.business),
    _FacetCategory(key: 'writer', label: 'Writer', icon: Icons.edit),
    _FacetCategory(key: 'penciller', label: 'Penciller', icon: Icons.brush),
    _FacetCategory(key: 'genre', label: 'Genre', icon: Icons.category),
    _FacetCategory(key: 'year', label: 'Year', icon: Icons.calendar_today),
  ];

  void _toggleFacet(String key) {
    HapticFeedback.selectionClick();
    setState(() {
      _expandedFacet = _expandedFacet == key ? null : key;
    });
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(libraryFilterProvider);

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final category = _categories[index];
          final isExpanded = _expandedFacet == category.key;
          final isActive = _isCategoryActive(category.key, filter);

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildCategoryTile(context, category, isExpanded, isActive),
              AnimatedSize(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOutCubic,
                child: isExpanded
                    ? _FacetValueList(
                        facet: category.key,
                        onTap: (value) => _handleValueTap(category.key, value),
                        selectedValue: _selectedValue(category.key, filter),
                        accent: widget.accent,
                      )
                    : const SizedBox.shrink(),
              ),
              Divider(height: 1, thickness: 1, color: context.scheme.hair),
            ],
          );
        },
        childCount: _categories.length,
      ),
    );
  }

  Widget _buildCategoryTile(
    BuildContext context,
    _FacetCategory category,
    bool isExpanded,
    bool isActive,
  ) {
    return ListTile(
      tileColor: context.scheme.s2,
      leading: Icon(
        category.icon,
        size: 20,
        color: isActive ? widget.accent : context.scheme.t3,
      ),
      title: Text(
        category.label,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: isActive ? widget.accent : context.scheme.tx,
        ),
      ),
      trailing: Icon(
        isExpanded ? Icons.expand_less : Icons.expand_more,
        size: 20,
        color: context.scheme.t3,
      ),
      onTap: () => _toggleFacet(category.key),
    );
  }

  bool _isCategoryActive(String key, LibraryFilter filter) {
    switch (key) {
      case 'publisher':
        return filter.publisher != null;
      case 'writer':
        return filter.writer != null;
      case 'genre':
        return filter.genre != null;
      case 'penciller':
        return filter.penciller != null;
      case 'year':
        return filter.yearMin != null || filter.yearMax != null;
      default:
        return false;
    }
  }

  String? _selectedValue(String key, LibraryFilter filter) {
    switch (key) {
      case 'publisher':
        return filter.publisher;
      case 'writer':
        return filter.writer;
      case 'genre':
        return filter.genre;
      case 'penciller':
        return filter.penciller;
      case 'year':
        if (filter.yearMin != null) return filter.yearMin.toString();
        return null;
      default:
        return null;
    }
  }

  void _handleValueTap(String facet, String value) {
    HapticFeedback.selectionClick();
    final notifier = ref.read(libraryFilterProvider.notifier);
    switch (facet) {
      case 'publisher':
        final current = ref.read(libraryFilterProvider).publisher;
        notifier.setPublisher(current == value ? null : value);
      case 'writer':
        final current = ref.read(libraryFilterProvider).writer;
        notifier.setWriter(current == value ? null : value);
      case 'genre':
        final current = ref.read(libraryFilterProvider).genre;
        notifier.setGenre(current == value ? null : value);
      case 'penciller':
        final current = ref.read(libraryFilterProvider).penciller;
        notifier.setPenciller(current == value ? null : value);
      case 'year':
        final yearInt = int.tryParse(value);
        if (yearInt == null) return;
        final filter = ref.read(libraryFilterProvider);
        final alreadySelected =
            filter.yearMin == yearInt && filter.yearMax == yearInt;
        if (alreadySelected) {
          notifier.setYearRange(null, null);
        } else {
          notifier.setYearRange(yearInt, yearInt);
        }
    }
  }
}

// ---------------------------------------------------------------------------
// Private data class
// ---------------------------------------------------------------------------

class _FacetCategory {
  final String key;
  final String label;
  final IconData icon;

  const _FacetCategory({
    required this.key,
    required this.label,
    required this.icon,
  });
}

// ---------------------------------------------------------------------------
// Private child widget — renders the expanded value list for one facet
// ---------------------------------------------------------------------------

class _FacetValueList extends ConsumerWidget {
  final String facet;
  final void Function(String value) onTap;
  final String? selectedValue;
  final Color accent;

  const _FacetValueList({
    required this.facet,
    required this.onTap,
    required this.selectedValue,
    this.accent = AppTheme.accent,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(facetProvider(facet));

    return Container(
      color: context.scheme.s2,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: async.when(
        loading: () => Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: accent,
              ),
            ),
          ),
        ),
        error: (err, _) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'Failed to load facets',
            style: TextStyle(
              fontSize: 13,
              color: context.scheme.t3,
            ),
          ),
        ),
        data: (values) {
          if (values.isEmpty) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No values',
                style: TextStyle(fontSize: 13, color: context.scheme.t3),
              ),
            );
          }
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: values.map((fv) {
              final isSelected = selectedValue == fv.value;
              return _FacetChip(
                label: '${fv.value} (${fv.count})',
                selected: isSelected,
                accent: accent,
                onTap: () => onTap(fv.value),
              );
            }).toList(),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Chip widget
// ---------------------------------------------------------------------------

class _FacetChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color accent;

  const _FacetChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.accent = AppTheme.accent,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? accent.withAlpha(40) : context.scheme.s3,
          borderRadius: BorderRadius.circular(AppTheme.r20),
          border: Border.all(
            color: selected ? accent : context.scheme.borderFaint,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? accent : context.scheme.t2,
          ),
        ),
      ),
    );
  }
}
