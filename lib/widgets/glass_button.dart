import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'liquid_glass.dart';

class GlassButton extends StatelessWidget {
  static const double minTapSize = 44;

  final Widget child;
  final VoidCallback? onTap;
  final double size;

  /// Accessible name for icon-only buttons (VoiceOver + long-press tooltip).
  final String? label;

  const GlassButton({
    super.key,
    required this.child,
    this.onTap,
    this.size = 36,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    final button = Semantics(
      button: true,
      label: label,
      // The hit box is at least 44pt (Apple's minimum); the glass stays
      // [size] and is centered in it. Callers trim their padding to match.
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox.square(
          dimension: math.max(size, minTapSize),
          child: Center(
            child: LiquidGlass(
              radius: size / 2,
              child: SizedBox(
                width: size,
                height: size,
                child: Center(child: child),
              ),
            ),
          ),
        ),
      ),
    );
    return label == null ? button : Tooltip(message: label!, excludeFromSemantics: true, child: button);
  }
}
