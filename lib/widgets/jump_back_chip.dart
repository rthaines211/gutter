import 'package:flutter/material.dart';
import '../config/scheme.dart';
import 'liquid_glass.dart';

/// "Back to page N" after a reader jump; flips to "Forward to page M" once
/// tapped. [page] is the 1-based page the tap leads to.
class JumpBackChip extends StatelessWidget {
  final int page;
  final bool forward;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  const JumpBackChip({
    super.key,
    required this.page,
    required this.forward,
    required this.onTap,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final style = TextStyle(
        color: scheme.tx, fontSize: 14, fontWeight: FontWeight.w600);
    final icon = Icon(forward ? Icons.redo : Icons.undo, size: 18, color: scheme.tx);
    return LiquidGlass(
      radius: 22,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            button: true,
            child: GestureDetector(
              key: const Key('jumpchip.action'),
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Padding(
                  padding: const EdgeInsets.only(left: 16, right: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!forward) ...[icon, const SizedBox(width: 8)],
                      Text(
                        forward ? 'Forward to page $page' : 'Back to page $page',
                        style: style,
                      ),
                      if (forward) ...[const SizedBox(width: 8), icon],
                    ],
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            width: 44,
            height: 44,
            child: IconButton(
              key: const Key('jumpchip.dismiss'),
              tooltip: 'Dismiss',
              padding: EdgeInsets.zero,
              iconSize: 16,
              color: scheme.t2,
              onPressed: onDismiss,
              icon: const Icon(Icons.close),
            ),
          ),
        ],
      ),
    );
  }
}
