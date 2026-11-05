import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/app_theme.dart';
import '../config/comic_style.dart';
import '../config/scheme.dart';

/// Pinned A–Z letter header for the library grid.
class LibrarySectionHeaderDelegate extends SliverPersistentHeaderDelegate {
  final String label;
  final int count;
  // Lets the index rail (Task 5) locate this header with Scrollable.ensureVisible.
  final Key? headerKey;
  final Color accent;

  const LibrarySectionHeaderDelegate({
    required this.label,
    required this.count,
    this.headerKey,
    this.accent = AppTheme.accent,
  });

  static const _height = 36.0;

  @override
  double get minExtent => _height;

  @override
  double get maxExtent => _height;

  // The look lives in its own widget: theme reads here, in the delegate's
  // build, went stale on a theme switch (sepia headers left in OLED black),
  // while widgets below it picked the new theme up.
  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) =>
      _SectionHeader(label: label, count: count, headerKey: headerKey, accent: accent);

  @override
  bool shouldRebuild(LibrarySectionHeaderDelegate old) =>
      old.label != label || old.count != count || old.headerKey != headerKey;
}

class _SectionHeader extends StatelessWidget {
  final String label;
  final int count;
  final Key? headerKey;
  final Color accent;

  const _SectionHeader({required this.label, required this.count, this.headerKey, required this.accent});

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return Container(
      key: headerKey,
      height: LibrarySectionHeaderDelegate._height,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: scheme.bg,
        border: Border(bottom: BorderSide(color: scheme.hair, width: 0.5)),
      ),
      child: Consumer(
        builder: (context, ref, _) {
          final comic = ComicTokens.watch(ref, context, accent);
          return Row(
            children: [
              Text(
                label,
                style: AppTheme.displayTextStyle(comic, fontSize: 17)
                    .copyWith(color: scheme.tx, letterSpacing: -0.2),
              ),
              const SizedBox(width: 8),
              Text('$count', style: context.monoCaption),
            ],
          );
        },
      ),
    );
  }
}
