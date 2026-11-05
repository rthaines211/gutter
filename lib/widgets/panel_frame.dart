import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/app_theme.dart';
import '../config/comic_style.dart';

class PanelFrame extends ConsumerWidget {
  final Widget child;
  final double radius;
  final Color? tint;
  final List<BoxShadow>? extraShadows;
  final Color accent;

  const PanelFrame({
    super.key,
    required this.child,
    this.radius = 14,
    this.tint,
    this.extraShadows,
    this.accent = AppTheme.accent,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final comic = ComicTokens.watch(ref, context, accent);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: comic.ink, width: comic.borderWidth),
        boxShadow:
            extraShadows ??
            (comic.hardShadow ? comic.cardShadow : _glassShadows()),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: child,
      ),
    );
  }

  List<BoxShadow> _glassShadows() => [
    BoxShadow(
      color: Colors.white.withValues(alpha: 0.10),
      offset: const Offset(0, 0.5),
      blurRadius: 0,
    ),
    const BoxShadow(
      color: Color(0x80000000),
      offset: Offset(0, -0.5),
      blurRadius: 0,
    ),
    const BoxShadow(
      color: Color(0x8C000000),
      offset: Offset(0, 14),
      blurRadius: 32,
    ),
    if (tint != null)
      BoxShadow(
        color: tint!.withValues(alpha: 0.33),
        offset: const Offset(0, 20),
        blurRadius: 48,
      ),
  ];
}
