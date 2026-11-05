import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/scheme.dart';

class LiquidGlass extends ConsumerWidget {
  final Widget child;
  final double radius;
  final double intensity;
  final Color? tint;
  final EdgeInsetsGeometry? padding;

  /// Overrides [radius] for non-uniform corners (a sheet rounds only its top).
  final BorderRadius? borderRadius;

  const LiquidGlass({
    super.key,
    required this.child,
    this.radius = 22,
    this.intensity = 28,
    this.tint,
    this.padding,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = context.scheme;
    final corners = borderRadius ?? BorderRadius.circular(radius);
    return ClipRRect(
      borderRadius: corners,
      child: BackdropFilter(
        filter: ImageFilter.compose(
          outer: ImageFilter.blur(sigmaX: intensity, sigmaY: intensity),
          inner: ColorFilter.mode(
            Colors.white.withValues(alpha: 0.1),
            scheme.dark ? BlendMode.overlay : BlendMode.srcOver,
          ),
        ),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: tint ?? scheme.glass,
            borderRadius: corners,
            border: Border.all(color: scheme.hair, width: 0.5),
            boxShadow: [
              BoxShadow(
                color: scheme.hairStrong,
                offset: const Offset(0, 0.5),
                blurRadius: 0,
              ),
              const BoxShadow(
                color: Color(0x80000000),
                offset: Offset(0, 12),
                blurRadius: 32,
              ),
              const BoxShadow(
                color: Color(0x59000000),
                offset: Offset(0, 2),
                blurRadius: 6,
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}
