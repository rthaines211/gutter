import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Where [panel] (page pixels) sits on the contain-fit [page] on screen, kept
/// inside the page: the detector sometimes overshoots an edge.
Rect panelOnScreen(Rect page, Size pagePx, Rect panel) {
  final s = page.width / pagePx.width;
  return Rect.fromLTRB(
    page.left + panel.left.clamp(0, pagePx.width) * s,
    page.top + panel.top.clamp(0, pagePx.height) * s,
    page.left + panel.right.clamp(0, pagePx.width) * s,
    page.top + panel.bottom.clamp(0, pagePx.height) * s,
  );
}

/// Panel zoom steps: step 0 is the whole page, then one per panel.
///
/// Fit ([popout] false, the phone): each step scales the page so the panel,
/// with 8 px of screen around it, fits the screen, and centres on it. The
/// scale never drops below the contain fit (a panel wider than the screen
/// letterboxes at page scale), and the page is never pulled off the screen
/// edge it covers, so no blank strip shows past it.
///
/// Pop-out ([popout] true, the iPad): every step is the identity; the overlay
/// lifts the panel out and the page stays put.
List<Matrix4> panelSteps({
  required Rect page,
  required Size pagePx,
  required Size screen,
  required List<Rect> panels,
  required bool popout,
}) {
  if (popout) return List.filled(panels.length + 1, Matrix4.identity());
  const margin = 8.0;
  return [
    Matrix4.identity(),
    for (final p in panels)
      () {
        final r = panelOnScreen(page, pagePx, p);
        final k = math.max(
          1.0,
          math.min(
            (screen.width - 2 * margin) / math.max(1, r.width),
            (screen.height - 2 * margin) / math.max(1, r.height),
          ),
        );
        return Matrix4.identity()
          ..setEntry(0, 0, k)
          ..setEntry(1, 1, k)
          ..setEntry(0, 3, _offset(screen.width / 2 - k * r.center.dx, page.left * k, page.right * k, screen.width))
          ..setEntry(1, 3, _offset(screen.height / 2 - k * r.center.dy, page.top * k, page.bottom * k, screen.height));
      }(),
  ];
}

/// [want] translation, unless the scaled page (spanning [lo]..[hi] before
/// translation) would then leave the screen edge: a page smaller than the
/// screen is centred; a bigger one is kept covering it.
double _offset(double want, double lo, double hi, double extent) {
  if (hi - lo <= extent) return (extent - (hi - lo)) / 2 - lo;
  return want.clamp(extent - hi, -lo);
}

/// The panel under [point] (page pixels): the smallest one holding it, since
/// the detector sometimes nests an inset inside its panel. Null off every panel.
Rect? panelAt(List<Rect> panels, Offset point) {
  Rect? best;
  for (final p in panels) {
    if (!p.contains(point)) continue;
    if (best == null || p.width * p.height < best.width * best.height) best = p;
  }
  return best;
}
