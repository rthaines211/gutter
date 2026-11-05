import 'package:flutter/material.dart';
import '../config/scheme.dart';

class ThemedIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final double size;

  const ThemedIconButton({
    super.key,
    required this.icon,
    this.onTap,
    this.size = 36,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: context.scheme.s2,
          shape: BoxShape.circle,
          border: Border.all(
            color: context.scheme.borderFaint,
            width: 0.5,
          ),
        ),
        child: Icon(icon, size: 17, color: context.scheme.t2),
      ),
    );
  }
}
