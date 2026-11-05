import 'dart:ui' show PointMode;

import 'package:flutter/material.dart';

class HalftoneOverlay extends StatelessWidget {
  final double opacity;
  final Color color;
  final double dotSpacing;

  /// Painted dot radius. Defaults to the historical `dotSpacing * 0.12`
  /// (null preserves that relationship for existing callers); pass an
  /// explicit value to decouple the dot size from the tile spacing, e.g.
  /// the Ben-Day hero overlay (radius 1.6 @ spacing 9).
  final double? dotRadius;

  final BlendMode? blendMode;

  const HalftoneOverlay({
    super.key,
    this.opacity = 0.08,
    this.color = Colors.white,
    this.dotSpacing = 6,
    this.dotRadius,
    this.blendMode,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        // Static dot field: isolate it so sibling repaints don't redraw it.
        child: RepaintBoundary(
          child: CustomPaint(
            painter: _HalftonePainter(
              color: color.withValues(alpha: opacity),
              spacing: dotSpacing,
              dotRadius: dotRadius ?? dotSpacing * 0.12,
              blendMode: blendMode,
            ),
          ),
        ),
      ),
    );
  }
}

class _HalftonePainter extends CustomPainter {
  final Color color;
  final double spacing;
  final double dotRadius;
  final BlendMode? blendMode;

  _HalftonePainter({
    required this.color,
    required this.spacing,
    required this.dotRadius,
    this.blendMode,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // ponytail: one drawPoints beats ~10k drawCircle calls. A round-cap
    // point of width 2r is the same dot; the hero used to spend >1s/frame
    // here. Offsets are rebuilt only when size/spacing change.
    final paint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..strokeWidth = dotRadius * 2;
    if (blendMode != null) paint.blendMode = blendMode!;

    if (_cached == null || _cachedSize != size || _cachedSpacing != spacing) {
      final dots = <Offset>[];
      for (double y = 0; y < size.height; y += spacing) {
        for (double x = 0; x < size.width; x += spacing) {
          dots.add(Offset(x + spacing / 2, y + spacing / 2));
        }
      }
      _cached = dots;
      _cachedSize = size;
      _cachedSpacing = spacing;
    }

    canvas.drawPoints(PointMode.points, _cached!, paint);
  }

  List<Offset>? _cached;
  Size? _cachedSize;
  double? _cachedSpacing;

  @override
  bool shouldRepaint(_HalftonePainter old) =>
      old.color != color ||
      old.spacing != spacing ||
      old.dotRadius != dotRadius ||
      old.blendMode != blendMode;
}
