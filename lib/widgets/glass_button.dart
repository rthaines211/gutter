import 'package:flutter/material.dart';
import 'liquid_glass.dart';

class GlassButton extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double size;

  const GlassButton({
    super.key,
    required this.child,
    this.onTap,
    this.size = 36,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: LiquidGlass(
        radius: size / 2,
        child: SizedBox(
          width: size,
          height: size,
          child: Center(child: child),
        ),
      ),
    );
  }
}
