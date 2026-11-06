import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/app_theme.dart';
import '../config/scheme.dart';

/// Always-visible search bar with inline Filter button.
/// 38px height, surface1 background, r12.
class LibrarySearchBar extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onFilterTap;
  final int activeFilterCount;
  final Color accent;

  const LibrarySearchBar({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.onFilterTap,
    this.activeFilterCount = 0,
    this.accent = AppTheme.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: context.scheme.s1,
        borderRadius: BorderRadius.circular(AppTheme.r12),
        border: Border.all(
          color: context.scheme.borderFaint,
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 12),
          Icon(Icons.search, size: 14, color: context.scheme.t3),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              style: TextStyle(color: context.scheme.tx, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search series, issue, writer\u2026',
                hintStyle: TextStyle(color: context.scheme.t3, fontSize: 14),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              onChanged: onChanged,
            ),
          ),
          if (controller.text.isNotEmpty)
            Semantics(
              button: true,
              label: 'Clear search',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  controller.clear();
                  onChanged('');
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.close, size: 14, color: context.scheme.t3),
                ),
              ),
            ),
          GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              onFilterTap();
            },
            child: Container(
              height: 24,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                color: activeFilterCount > 0
                    ? AppTheme.accentSoft(accent)
                    : context.scheme.s2,
                borderRadius: BorderRadius.circular(AppTheme.r8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.tune_rounded, size: 11,
                      color: activeFilterCount > 0 ? accent : context.scheme.t2),
                  const SizedBox(width: 4),
                  Text(
                    activeFilterCount > 0 ? 'Filter ($activeFilterCount)' : 'Filter',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: activeFilterCount > 0 ? accent : context.scheme.t2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
