import 'package:flutter/material.dart';

/// Panel zoom's "dim around panel": the screen at 60 % black with [hole] (the
/// current panel, screen coordinates) left clear. A null hole fades it out.
/// Sits above the page and below the pop-out; never takes a touch.
class PanelDimOverlay extends StatelessWidget {
  const PanelDimOverlay({super.key, required this.hole});

  final Rect? hole;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: hole == null ? 0 : 1,
        duration: const Duration(milliseconds: 150),
        child: CustomPaint(
          size: Size.infinite,
          painter: PanelDimPainter(hole ?? Rect.zero),
        ),
      ),
    );
  }
}

class PanelDimPainter extends CustomPainter {
  const PanelDimPainter(this.hole);

  final Rect hole;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(RRect.fromRectAndRadius(hole, const Radius.circular(4)))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, Paint()..color = Colors.black.withValues(alpha: 0.6));
  }

  @override
  bool shouldRepaint(PanelDimPainter old) => old.hole != hole;
}
