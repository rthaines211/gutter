import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/app_theme.dart';
import '../config/scheme.dart';
import '../providers/facet_provider.dart';
import '../providers/library_provider.dart';

class FacetPickerSheet extends ConsumerStatefulWidget {
  final Color accent;

  const FacetPickerSheet({super.key, this.accent = AppTheme.accent});

  @override
  ConsumerState<FacetPickerSheet> createState() => _FacetPickerSheetState();
}

class _FacetPickerSheetState extends ConsumerState<FacetPickerSheet> {
  final _expanded = <String, bool>{
    'publisher': false,
    'writer': false,
    'penciller': false,
    'genre': false,
    'year': false,
  };

  final _queries = <String, String>{
    'publisher': '',
    'writer': '',
    'penciller': '',
    'genre': '',
    'year': '',
  };

  final _searchControllers = <String, TextEditingController>{};

  @override
  void initState() {
    super.initState();
    for (final key in _queries.keys) {
      _searchControllers[key] = TextEditingController();
    }
  }

  @override
  void dispose() {
    for (final c in _searchControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(libraryFilterProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: context.scheme.s2,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          children: [
            // Handle
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 12),
              decoration: BoxDecoration(
                color: context.scheme.hairStrong,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 16, 12),
              child: Row(
                children: [
                  Text('Filters',
                      style: TextStyle(
                          color: context.scheme.tx,
                          fontSize: 16,
                          fontWeight: FontWeight.w600)),
                  const Spacer(),
                  if (filter.activeFilterCount > 0)
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        ref.read(libraryFilterProvider.notifier).clearMetadataFilters();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: widget.accent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: widget.accent.withValues(alpha: 0.3),
                            width: 0.5,
                          ),
                        ),
                        child: Text('Clear All',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: widget.accent)),
                      ),
                    ),
                ],
              ),
            ),
            Divider(color: context.scheme.hair, height: 1),
            // Facet sections
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.only(bottom: 40),
                children: [
                  _buildFacetSection(
                    context,
                    label: 'PUBLISHER',
                    facetKey: 'publisher',
                    currentValue: filter.publisher,
                    onSelect: (v) =>
                        ref.read(libraryFilterProvider.notifier).setPublisher(v),
                  ),
                  _buildFacetSection(
                    context,
                    label: 'WRITER',
                    facetKey: 'writer',
                    currentValue: filter.writer,
                    onSelect: (v) =>
                        ref.read(libraryFilterProvider.notifier).setWriter(v),
                  ),
                  _buildFacetSection(
                    context,
                    label: 'PENCILLER',
                    facetKey: 'penciller',
                    currentValue: filter.penciller,
                    onSelect: (v) =>
                        ref.read(libraryFilterProvider.notifier).setPenciller(v),
                  ),
                  _buildFacetSection(
                    context,
                    label: 'GENRE',
                    facetKey: 'genre',
                    currentValue: filter.genre,
                    onSelect: (v) =>
                        ref.read(libraryFilterProvider.notifier).setGenre(v),
                  ),
                  _buildFacetSection(
                    context,
                    label: 'YEAR',
                    facetKey: 'year',
                    currentValue: filter.yearMin?.toString(),
                    onSelect: (v) {
                      final year = int.tryParse(v ?? '');
                      ref.read(libraryFilterProvider.notifier).setYearRange(year, year);
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFacetSection(
    BuildContext context, {
    required String label,
    required String facetKey,
    required String? currentValue,
    required void Function(String?) onSelect,
  }) {
    final isExpanded = _expanded[facetKey] ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() => _expanded[facetKey] = !isExpanded);
          },
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Text(label, style: context.sectionHeader),
                      if (currentValue != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: widget.accent.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(currentValue,
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: widget.accent),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1),
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(
                  isExpanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 18,
                  color: context.scheme.t3,
                ),
              ],
            ),
          ),
        ),
        if (isExpanded)
          _buildFacetContent(context, facetKey, currentValue, onSelect),
        Divider(color: context.scheme.hair, height: 1),
      ],
    );
  }

  Widget _buildFacetContent(
    BuildContext context,
    String facetKey,
    String? currentValue,
    void Function(String?) onSelect,
  ) {
    final facetAsync = ref.watch(facetProvider(facetKey));
    final query = _queries[facetKey] ?? '';

    return Column(
      children: [
        // Search box
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Container(
            height: 36,
            decoration: BoxDecoration(
              color: context.scheme.s1,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: context.scheme.borderFaint,
                width: 0.5,
              ),
            ),
            child: Row(
              children: [
                const SizedBox(width: 10),
                Icon(Icons.search, size: 14, color: context.scheme.t3),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _searchControllers[facetKey],
                    style: TextStyle(color: context.scheme.tx, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Search...',
                      hintStyle: TextStyle(color: context.scheme.t3, fontSize: 13),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    onChanged: (v) => setState(() => _queries[facetKey] = v),
                  ),
                ),
                if (query.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      _searchControllers[facetKey]?.clear();
                      setState(() => _queries[facetKey] = '');
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Icon(Icons.close, size: 12, color: context.scheme.t3),
                    ),
                  ),
              ],
            ),
          ),
        ),
        // Values
        facetAsync.when(
          loading: () => Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: widget.accent),
              ),
            ),
          ),
          error: (e, st) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
            child: Text('Failed to load',
                style: TextStyle(color: context.scheme.t3, fontSize: 12)),
          ),
          data: (values) {
            final filtered = query.isEmpty
                ? values
                : values
                    .where((v) =>
                        v.value.toLowerCase().contains(query.toLowerCase()))
                    .toList();

            if (filtered.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
                child: Text('No results',
                    style: TextStyle(color: context.scheme.t3, fontSize: 12)),
              );
            }

            final displayValues =
                filtered.length > 8 ? filtered.take(8).toList() : filtered;
            final truncated = filtered.length > 8;

            return Column(
              children: [
                if (currentValue != null)
                  _facetValueRow(
                    context,
                    label: 'Any',
                    count: null,
                    selected: false,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      onSelect(null);
                    },
                    isAny: true,
                  ),
                ...displayValues.map((fv) {
                  final selected = currentValue == fv.value;
                  return _facetValueRow(
                    context,
                    label: fv.value,
                    count: fv.count,
                    selected: selected,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      onSelect(selected ? null : fv.value);
                    },
                  );
                }),
                if (truncated)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                    child: Text(
                      '+${filtered.length - 8} more — search to narrow',
                      style: TextStyle(fontSize: 11, color: context.scheme.t3),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 4),
      ],
    );
  }

  Widget _facetValueRow(
    BuildContext context, {
    required String label,
    required int? count,
    required bool selected,
    required VoidCallback onTap,
    bool isAny = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Row(
          children: [
            Icon(
              selected ? Icons.check_circle_rounded : Icons.circle_outlined,
              size: 16,
              color: selected ? widget.accent : context.scheme.t3,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: isAny
                        ? context.scheme.t3
                        : (selected ? context.scheme.tx : context.scheme.t2),
                    fontStyle: isAny ? FontStyle.italic : FontStyle.normal,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1),
            ),
            if (count != null)
              Text('$count',
                  style: TextStyle(
                      fontSize: 11,
                      color: context.scheme.t3,
                      fontFamily: '.SF Mono')),
          ],
        ),
      ),
    );
  }
}
