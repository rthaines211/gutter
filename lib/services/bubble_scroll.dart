import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../widgets/bubble_pop_overlay.dart';

/// Balloon steps for a page shown larger than the screen (fit width on a
/// sideways screen): every step keeps [scale] and scrolls the page vertically.
///
/// [steps] are each step's balloons on the unmoved, contain-fit page: their
/// crops together, and the tail tip when there is one. [page] is that page's
/// contain rect. Step 0 shows the top of the page. A step only scrolls when its
/// balloon, or its pop-out grown out of the tail, isn't fully on screen; then
/// the balloon lands near the top so what follows it is in view, but never
/// more than most of a screen at a time going down, so no art is skipped. The
/// scroll stays within the page; a pop-out that needs more room slides it past
/// its edge, as in portrait. A last step shows the bottom of the page when the
/// balloons never reach it.
List<Matrix4> bubbleScrollSteps({
  required double scale,
  required Rect page,
  required Size screen,
  required List<(Rect, Offset?)> steps,
}) {
  final h = screen.height;
  final tx = (screen.width - page.width * scale) / 2 - page.left * scale;
  // The page covers the screen top to bottom: ty runs from showing its top
  // to showing its bottom (or, if it isn't taller than the screen, centred).
  var top = -page.top * scale, bottom = h - page.bottom * scale;
  if (bottom > top) {
    top = bottom = (h - page.height * scale) / 2 - page.top * scale;
  }

  Matrix4 at(double dx, double y) => Matrix4.identity()
    ..setEntry(0, 0, scale)
    ..setEntry(1, 1, scale)
    ..setEntry(0, 3, tx + dx)
    ..setEntry(1, 3, y);
  Rect scaled(Rect r) => Rect.fromLTRB(
    r.left * scale + tx,
    r.top * scale,
    r.right * scale + tx,
    r.bottom * scale,
  );

  var ty = top;
  final out = [at(0, ty)];
  for (final (on, tail) in steps) {
    // What has to be on screen, at ty = 0: the balloon, and a tailed pop-out.
    final b = scaled(on);
    final t = tail == null
        ? null
        : Offset(tail.dx * scale + tx, tail.dy * scale);
    final need = t == null
        ? b
        : b.expandToInclude(popoutRect(b, screen, tail: t, clamp: false));
    if (need.top + ty < 8 || need.bottom + ty > h - 8) {
      final next = math.max(
        8 + 0.1 * h - need.top,
        ty - 0.85 * h,
      ); // ponytail: 10 % headroom, 15 % overlap
      ty = need.bottom + next > h - 8 ? h - 8 - need.bottom : next;
      ty = ty.clamp(bottom, top);
    }
    // As in portrait, a pop-out may need the page past its own edge: slide it.
    final slide = t == null
        ? Offset.zero
        : popoutSlide(
            popoutRect(
              b.shift(Offset(0, ty)),
              screen,
              tail: t.translate(0, ty),
              clamp: false,
            ),
            screen,
          );
    out.add(at(slide.dx, ty + slide.dy));
  }
  if (ty > bottom + 1) out.add(at(0, bottom));
  return out;
}
