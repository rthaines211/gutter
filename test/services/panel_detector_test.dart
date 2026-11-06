import 'dart:typed_data';
import 'dart:ui';

import 'package:comic_reader_app/services/panel_detector.dart';
import 'package:flutter_test/flutter_test.dart';

/// One raw row per box: (x0, y0, x1, y1) in 640-px input space, objectness, panel score.
Float32List raw(List<List<double>> rows) => Float32List.fromList([
  for (final r in rows) ...[(r[0] + r[2]) / 2, (r[1] + r[3]) / 2, r[2] - r[0], r[3] - r[1], r[4], r[5]],
]);

void main() {
  test('cutoff, NMS and scale back to page pixels', () {
    // 1280x1280 page: r = 0.5, so input px x2 = page px.
    final out = panelsFromRaw(
      raw([
        [10, 10, 300, 300, 0.9, 0.9], // kept
        [12, 12, 302, 302, 0.9, 0.8], // same panel, lower score: suppressed
        [330, 10, 630, 300, 0.5, 0.5], // 0.25 < cutoff: dropped
      ]),
      width: 1280,
      height: 1280,
    );
    expect(out, [const Rect.fromLTRB(20, 20, 600, 600)]);
  });

  test('boxes clamp to the page', () {
    final out = panelsFromRaw(raw([[-5, -5, 700, 300, 1, 1]]), width: 640, height: 640);
    expect(out, [const Rect.fromLTRB(0, 0, 640, 300)]);
  });

  test('a grid reads left to right, then down', () {
    const tl = Rect.fromLTRB(0, 0, 100, 100), tr = Rect.fromLTRB(110, 0, 200, 100);
    const bl = Rect.fromLTRB(0, 110, 100, 200), br = Rect.fromLTRB(110, 110, 200, 200);
    expect(orderPanels([br, bl, tr, tl], width: 200, height: 300), [tl, tr, bl, br]);
  });

  test('a spread reads the left page, then the right', () {
    const leftLow = Rect.fromLTRB(0, 500, 400, 900), rightHigh = Rect.fromLTRB(600, 0, 1000, 400);
    expect(orderPanels([rightHigh, leftLow], width: 1000, height: 900), [leftLow, rightHigh]);
  });

  test('fold drops an inset inside a bigger panel', () {
    const host = Rect.fromLTRB(0, 0, 200, 200), inset = Rect.fromLTRB(10, 10, 60, 60);
    expect(orderPanels([host, inset], width: 200, height: 300, fold: true), [host]);
    expect(orderPanels([host, inset], width: 200, height: 300).length, 2);
  });
}
