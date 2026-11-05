import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../config/comic_style.dart';

/// Tilted yellow caption tag (fullPop) or a plain dark pill (off/inkHalftone).
///
/// Sits on cover art, not a themed surface, so its fill and text colours are
/// literal in every scheme — see docs/superpowers/DEFERRED.md "The scrim bug
/// class". Only the border uses a token ([ComicTokens.ink]) since that is not
/// a scheme lookup.
///
/// Covers the CONTINUE, NEXT, NEW tags and the series status pill.
class CaptionBox extends StatelessWidget {
  final String text;
  final ComicTokens comic;
  final bool rightSide;
  final IconData? icon;

  /// Replaces the [text] row for bigger captions (the sleep warning's
  /// countdown); it inherits the caption's text colour.
  final Widget? child;

  const CaptionBox({
    super.key,
    this.text = '',
    required this.comic,
    this.rightSide = false,
    this.icon,
    this.child,
  });

  static const _tiltDegrees = 2.0;

  @override
  Widget build(BuildContext context) {
    final fullPop = comic.captionBoxes;
    final fg = fullPop ? const Color(0xFF111111) : Colors.white;

    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: fullPop ? const Color(0xFFFFE14D) : const Color(0x73000000),
        borderRadius: BorderRadius.circular(fullPop ? 3 : 999),
        border: fullPop
            ? Border.all(color: comic.ink, width: comic.borderWidth)
            : null,
      ),
      child: child != null
          ? DefaultTextStyle.merge(style: TextStyle(color: fg), child: child!)
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 12, color: fg),
                  const SizedBox(width: 4),
                ],
                Text(
                  text,
                  style: TextStyle(
                    color: fg,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
    );

    if (!fullPop) return content;

    final degrees = rightSide ? _tiltDegrees : -_tiltDegrees;
    return Transform.rotate(
      angle: degrees * math.pi / 180,
      child: content,
    );
  }
}
