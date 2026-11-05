import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/app_theme.dart';
import '../config/scheme.dart';
import '../providers/collection_provider.dart';

class CollectionChipBar extends ConsumerWidget {
  final Color accent;

  const CollectionChipBar({super.key, this.accent = AppTheme.accent});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collectionsAsync = ref.watch(collectionsProvider);
    final activeId = ref.watch(activeCollectionProvider);

    return collectionsAsync.when(
      data: (collections) {
        if (collections.isEmpty) return const SizedBox.shrink();
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Row(
            children: [
              _buildChip(
                context: context,
                label: 'All',
                active: activeId == null,
                onTap: () {
                  HapticFeedback.selectionClick();
                  ref.read(activeCollectionProvider.notifier).select(null);
                },
              ),
              ...collections.map((c) => _buildChip(
                    context: context,
                    label: c.name,
                    active: activeId == c.id,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      ref.read(activeCollectionProvider.notifier).select(c.id);
                    },
                  )),
            ],
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (e, _) => const SizedBox.shrink(),
    );
  }

  Widget _buildChip({
    required BuildContext context,
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: active ? accent : context.scheme.s2,
            borderRadius: BorderRadius.circular(15),
            border: active
                ? null
                : Border.all(
                    color: context.scheme.borderFaint,
                    width: 0.5,
                  ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: active ? Scheme.onAccent(accent) : context.scheme.t2,
              ),
            ),
          ),
        ),
      ),
    );
  }

}
