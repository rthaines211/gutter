import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../models/page_bubbles.dart';

/// Where a page has detailed drawing, on a coarse grid: what a pop-out should
/// avoid covering. Flat fills, gutters and balloons are not art.
///
/// Spike 2026-10-11 (849 balloon steps, 112 pages, iPhone upright): placing a
/// 1.6x pop-out where it hides least of this cut the art it hides by a quarter
/// over placing it by its tail alone, and by 78 % over today's 2.6x.
class ArtMap {
  ArtMap(this.cell, this.cols, this.rows, this.bits);

  /// Grid cell size in page px.
  final int cell;
  final int cols, rows;

  /// 1 where the cell is detailed art.
  final Uint8List bits;

  /// Page px² of art under [r] (page px), not counting cells under [except].
  double cover(ui.Rect r, {ui.Rect? except}) {
    final x0 = (r.left / cell).floor().clamp(0, cols),
        x1 = (r.right / cell).ceil().clamp(0, cols);
    final y0 = (r.top / cell).floor().clamp(0, rows),
        y1 = (r.bottom / cell).ceil().clamp(0, rows);
    var n = 0;
    for (var y = y0; y < y1; y++) {
      for (var x = x0; x < x1; x++) {
        if (bits[y * cols + x] == 0) continue;
        if (except != null &&
            except.contains(ui.Offset((x + 0.5) * cell, (y + 0.5) * cell))) {
          continue;
        }
        n++;
      }
    }
    return n * cell * cell.toDouble();
  }
}

/// [artBits] for a page decoded as [rgba] ([w] x [h]). The grid is ~390 cells
/// wide, about one per point of an upright phone: the spike's scale.
Future<ArtMap> buildArtMap(PageBubbles pb, ui.Image page) async {
  final rgba = (await page.toByteData(
    format: ui.ImageByteFormat.rawRgba,
  ))!.buffer.asUint8List();
  final cell = (page.width / 390).floor().clamp(1, 64);
  final balloons = [for (final b in pb.bubbles) b.rect];
  final bits = await compute(_artJob, (
    rgba,
    page.width,
    page.height,
    cell,
    balloons,
  ));
  return ArtMap(
    cell,
    (page.width / cell).ceil(),
    (page.height / cell).ceil(),
    bits,
  );
}

Uint8List _artJob((Uint8List, int, int, int, List<ui.Rect>) j) =>
    artBits(j.$1, j.$2, j.$3, j.$4, j.$5);

/// Art cells: grey averaged per [cell] x [cell] block, then the step to the
/// left and upper neighbours, x4, averaged over 7 x 7 cells; above 40 is art.
/// Cells under [balloons] (page px) are cleared.
Uint8List artBits(
  Uint8List rgba,
  int w,
  int h,
  int cell,
  List<ui.Rect> balloons,
) {
  final cols = (w / cell).ceil(), rows = (h / cell).ceil();
  final sum = Float64List(cols * rows), cnt = Int32List(cols * rows);
  for (var y = 0; y < h; y++) {
    final row = (y ~/ cell) * cols;
    for (var x = 0; x < w; x++) {
      final o = (y * w + x) * 4, i = row + x ~/ cell;
      sum[i] += 0.299 * rgba[o] + 0.587 * rgba[o + 1] + 0.114 * rgba[o + 2];
      cnt[i]++;
    }
  }
  final g = Float64List(cols * rows);
  for (var i = 0; i < g.length; i++) {
    g[i] = sum[i] / cnt[i];
  }
  final e = Float64List(cols * rows);
  for (var y = 0; y < rows; y++) {
    for (var x = 0; x < cols; x++) {
      final i = y * cols + x;
      final dx = x > 0 ? (g[i] - g[i - 1]).abs() : 0.0,
          dy = y > 0 ? (g[i] - g[i - cols]).abs() : 0.0;
      e[i] = ((dx + dy) * 4).clamp(0, 255).toDouble();
    }
  }
  final out = Uint8List(cols * rows);
  for (var y = 0; y < rows; y++) {
    for (var x = 0; x < cols; x++) {
      var s = 0.0, n = 0;
      for (var yy = y - 3; yy <= y + 3; yy++) {
        for (var xx = x - 3; xx <= x + 3; xx++) {
          if (yy < 0 || xx < 0 || yy >= rows || xx >= cols) continue;
          s += e[yy * cols + xx];
          n++;
        }
      }
      if (s / n > 40) out[y * cols + x] = 1;
    }
  }
  for (final b in balloons) {
    for (
      var y = (b.top / cell).floor().clamp(0, rows);
      y < (b.bottom / cell).ceil().clamp(0, rows);
      y++
    ) {
      for (
        var x = (b.left / cell).floor().clamp(0, cols);
        x < (b.right / cell).ceil().clamp(0, cols);
        x++
      ) {
        out[y * cols + x] = 0;
      }
    }
  }
  return out;
}
