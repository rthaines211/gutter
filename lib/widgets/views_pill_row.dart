import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/app_theme.dart';
import '../config/scheme.dart';
import '../models/smart_filter.dart';
import '../providers/collection_provider.dart';
import '../providers/connectivity_provider.dart';
import '../providers/library_provider.dart';
import '../providers/smart_filter_provider.dart';
import 'smart_filter_editor.dart';

/// Unified horizontal pill row for library views.
/// Merges status filters (All, In Progress, Unread), smart filters,
/// and collections into one scrollable row.
class ViewsPillRow extends ConsumerWidget {
  final Color accent;

  const ViewsPillRow({super.key, this.accent = AppTheme.accent});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(libraryFilterProvider);
    final smartFilterView = ref.watch(librarySmartFilterProvider);
    final activeCollection = ref.watch(activeCollectionProvider);
    final smartFiltersAsync = ref.watch(smartFilterListProvider);
    final collectionsAsync = ref.watch(collectionsProvider);
    // Smart filters and collections need the server: offline, status only.
    final online = ref.watch(connectivityProvider);
    final smartFilters = online ? smartFiltersAsync.value ?? <SmartFilter>[] : <SmartFilter>[];
    final collections = online ? collectionsAsync.value ?? [] : [];

    final bool isSmartActive = smartFilterView.startsWith('smart:');
    final bool isCollectionActive = activeCollection != null && !isSmartActive;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Row(
        children: [
          // Built-in status views
          _Pill(
            icon: Icons.auto_stories_rounded,
            label: 'All',
            active: !isSmartActive && !isCollectionActive && filter.status == 'all',
            accent: accent,
            onTap: () => _selectStatus(ref, 'all'),
          ),
          const SizedBox(width: 6),
          _Pill(
            icon: Icons.play_arrow_rounded,
            label: 'In Progress',
            active: !isSmartActive && !isCollectionActive && filter.status == 'in_progress',
            accent: accent,
            onTap: () => _selectStatus(ref, 'in_progress'),
          ),
          const SizedBox(width: 6),
          _Pill(
            icon: Icons.auto_awesome,
            label: 'Unread',
            active: !isSmartActive && !isCollectionActive && filter.status == 'unread',
            accent: accent,
            onTap: () => _selectStatus(ref, 'unread'),
          ),
          const SizedBox(width: 6),
          _Pill(
            icon: Icons.download_done_rounded,
            label: 'On iPad',
            active: !isSmartActive && !isCollectionActive && filter.status == 'on_device',
            accent: accent,
            onTap: () => _selectStatus(ref, 'on_device'),
          ),
          // Smart filters
          ...smartFilters.map((sf) {
            final key = 'smart:${sf.id}';
            final active = smartFilterView == key;
            return Padding(
              padding: const EdgeInsets.only(left: 6),
              child: _Pill(
                label: sf.name,
                icon: Icons.filter_list,
                active: active,
                dotColor: active ? null : AppTheme.violet,
                accent: accent,
                onTap: () {
                  HapticFeedback.selectionClick();
                  final notifier = ref.read(librarySmartFilterProvider.notifier);
                  if (active) {
                    notifier.clear();
                  } else {
                    ref.read(activeCollectionProvider.notifier).select(null);
                    ref.read(libraryFilterProvider.notifier).setStatus('all');
                    notifier.select(sf.id);
                  }
                },
                onLongPress: () => _showSmartFilterOptions(context, ref, sf),
              ),
            );
          }),
          // Collections
          ...collections.map((c) {
            final active = isCollectionActive && activeCollection == c.id;
            return Padding(
              padding: const EdgeInsets.only(left: 6),
              child: _Pill(
                label: c.name,
                icon: Icons.bookmark_rounded,
                active: active,
                dotColor: active ? null : AppTheme.amber,
                accent: accent,
                onTap: () {
                  HapticFeedback.selectionClick();
                  if (active) {
                    ref.read(activeCollectionProvider.notifier).select(null);
                  } else {
                    ref.read(librarySmartFilterProvider.notifier).clear();
                    ref.read(libraryFilterProvider.notifier).setStatus('all');
                    ref.read(activeCollectionProvider.notifier).select(c.id);
                  }
                },
              ),
            );
          }),
          // "+" button
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => const SmartFilterEditor(),
              );
            },
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: context.scheme.hairStrong,
                  width: 0.5,
                  strokeAlign: BorderSide.strokeAlignInside,
                ),
              ),
              child: Center(
                child: Icon(Icons.add, size: 12, color: context.scheme.t3),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _selectStatus(WidgetRef ref, String status) {
    HapticFeedback.selectionClick();
    ref.read(librarySmartFilterProvider.notifier).clear();
    ref.read(activeCollectionProvider.notifier).select(null);
    ref.read(libraryFilterProvider.notifier).setStatus(status);
  }

  void _showSmartFilterOptions(BuildContext context, WidgetRef ref, SmartFilter sf) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: context.scheme.s2,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36, height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 16),
              decoration: BoxDecoration(
                color: ctx.scheme.hairStrong,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text(sf.name, style: TextStyle(color: context.scheme.tx, fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            ListTile(
              leading: Icon(Icons.edit, color: accent),
              title: Text('Edit', style: TextStyle(color: context.scheme.tx)),
              onTap: () {
                Navigator.pop(ctx);
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => SmartFilterEditor(existing: sf),
                );
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: Colors.red[400]),
              title: Text('Delete', style: TextStyle(color: Colors.red[400])),
              onTap: () async {
                Navigator.pop(ctx);
                HapticFeedback.mediumImpact();
                await ref.read(smartFilterNotifierProvider.notifier).delete(sf.id);
                final current = ref.read(librarySmartFilterProvider);
                if (current == 'smart:${sf.id}') {
                  ref.read(librarySmartFilterProvider.notifier).clear();
                }
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final IconData? icon;
  final String label;
  final bool active;
  final Color? dotColor;
  final Color accent;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _Pill({
    this.icon,
    required this.label,
    required this.active,
    this.dotColor,
    required this.accent,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: active ? accent : context.scheme.s1,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: active ? Colors.transparent : context.scheme.borderFaint,
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (dotColor != null && !active) ...[
              Container(
                width: 4, height: 4,
                decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
            ],
            if (icon != null) ...[
              Icon(icon, size: 11, color: active ? Scheme.onAccent(accent) : context.scheme.t3),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.1,
                color: active ? Scheme.onAccent(accent) : context.scheme.t2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
