import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The Longbox mark — "spines · pulled": three comic spines on a shelf with a
/// fourth tipped forward, as though pulled out to read.
///
/// Drawn rather than shipped as a raster so it stays crisp at any size and
/// picks up the live accent colour. The same geometry generates the iOS app
/// icon (see `assets/brand/longbox-mark.svg`), so the two never drift.
///
/// Geometry is authored on a 120×120 grid and scaled to [size].
class LongboxMark extends StatelessWidget {
  /// Edge length of the (square) mark.
  final double size;

  /// Colour of the pulled spine. Defaults to the app accent at the call site.
  final Color accent;

  /// Colour of the three upright spines and the shelf.
  final Color spineColor;

  /// Tile background. Null draws the mark with no ground, for placing on an
  /// existing surface.
  final Color? background;

  /// Corner radius of the tile. Ignored when [background] is null.
  final double radius;

  const LongboxMark({
    super.key,
    required this.size,
    required this.accent,
    this.spineColor = const Color(0xFFF8F0DD),
    this.background,
    this.radius = 8,
  });

  @override
  Widget build(BuildContext context) {
    final mark = CustomPaint(
      size: Size(size, size),
      painter: _LongboxMarkPainter(accent: accent, spineColor: spineColor),
    );
    if (background == null) return SizedBox.square(dimension: size, child: mark);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: mark,
    );
  }
}

class _LongboxMarkPainter extends CustomPainter {
  final Color accent;
  final Color spineColor;

  const _LongboxMarkPainter({required this.accent, required this.spineColor});

  /// The grid the geometry is authored on.
  static const _grid = 120.0;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / _grid;
    final spine = Paint()..color = spineColor;

    // Three upright spines.
    for (final r in const [
      Rect.fromLTWH(22, 26, 16, 68),
      Rect.fromLTWH(66, 30, 16, 64),
      Rect.fromLTWH(88, 36, 12, 58),
    ]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(r.left * k, r.top * k, r.width * k, r.height * k),
          Radius.circular(2 * k),
        ),
        spine,
      );
    }

    // The pulled spine, tipped -8° about (52, 56).
    canvas.save();
    canvas.translate(52 * k, 56 * k);
    canvas.rotate(-8 * math.pi / 180);
    canvas.translate(-52 * k, -56 * k);
    canvas.drawRect(
      Rect.fromLTWH(44 * k, 18 * k, 17 * k, 76 * k),
      Paint()..color = accent,
    );
    canvas.restore();

    // Shelf line beneath all four.
    canvas.drawLine(
      Offset(18 * k, 100 * k),
      Offset(102 * k, 100 * k),
      Paint()
        ..color = spineColor
        ..strokeWidth = 7 * k
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_LongboxMarkPainter old) =>
      old.accent != accent || old.spineColor != spineColor;
}
