import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../models/page_bubbles.dart';

/// Alpha (0 or 255 per pixel) of balloon [label] inside the box ([left], [top],
/// [bw] x [bh]) of a label image ([labels], one byte per pixel, [w] wide).
/// Interior holes (the lettering) are filled and the shape is grown by [grow] px
/// to cover the ink outline, as in the spike's frames2.py `balloon_mask`.
/// Null when [label] has no pixels in the box.
Uint8List? balloonAlpha(
  Uint8List labels,
  int w,
  int left,
  int top,
  int bw,
  int bh,
  int label, {
  int grow = 2,
}) {
  final inside = Uint8List(bw * bh);
  var any = false;
  for (var y = 0; y < bh; y++) {
    final row = (top + y) * w + left;
    for (var x = 0; x < bw; x++) {
      if (labels[row + x] == label) {
        inside[y * bw + x] = 1;
        any = true;
      }
    }
  }
  if (!any) return null;

  // Flood the outside from the border; whatever it can't reach is balloon or hole.
  final outside = Uint8List(bw * bh);
  final stack = <int>[];
  void seed(int i) {
    if (inside[i] == 0 && outside[i] == 0) {
      outside[i] = 1;
      stack.add(i);
    }
  }

  for (var x = 0; x < bw; x++) {
    seed(x);
    seed((bh - 1) * bw + x);
  }
  for (var y = 0; y < bh; y++) {
    seed(y * bw);
    seed(y * bw + bw - 1);
  }
  while (stack.isNotEmpty) {
    final i = stack.removeLast();
    final x = i % bw, y = i ~/ bw;
    if (x > 0) seed(i - 1);
    if (x < bw - 1) seed(i + 1);
    if (y > 0) seed(i - bw);
    if (y < bh - 1) seed(i + bw);
  }

  final out = Uint8List(bw * bh);
  for (var y = 0; y < bh; y++) {
    for (var x = 0; x < bw; x++) {
      if (outside[y * bw + x] == 1) continue;
      for (
        var yy = math.max(0, y - grow);
        yy <= math.min(bh - 1, y + grow);
        yy++
      ) {
        for (
          var xx = math.max(0, x - grow);
          xx <= math.min(bw - 1, x + grow);
          xx++
        ) {
          out[yy * bw + xx] = 255;
        }
      }
    }
  }
  return out;
}

/// The balloon's real shape at page resolution, from a crop of the page ([rgba],
/// [w] x [h]) and its [seed]: 1 where the host job's label is this balloon, 2
/// where it is another balloon, 0 elsewhere. The stored label is half resolution
/// and only the balloon's interior, notched wherever lettering runs close to the
/// edge, so: grow over pixels of the balloon's fill colour, take in the outline
/// by growing [outline] px, fill the lettering, and feather 1 px. Every balloon
/// on the crop grows at once and a pixel goes to whichever reaches it first, so
/// where balloons join with no outline between them the split falls at the
/// join. If the result runs on into the background, or the fill colour doesn't
/// hold, the stored region is used as is. Null when there is no seed.
/// Which sides of a crop are the page's own edge.
typedef PageEdges = ({bool left, bool top, bool right, bool bottom});
const PageEdges noPageEdges = (
  left: false,
  top: false,
  right: false,
  bottom: false,
);

Uint8List? balloonCutout(
  Uint8List rgba,
  int w,
  int h,
  Uint8List seed, {
  required int outline,
  PageEdges pageEdges = noPageEdges,
  (int, int, int, int)? tight,
}) {
  final n = w * h;
  final hist = List.generate(3, (_) => List<int>.filled(256, 0));
  var seedCount = 0;
  for (var i = 0; i < n; i++) {
    if (seed[i] != 1) continue;
    seedCount++;
    for (var c = 0; c < 3; c++) {
      hist[c][rgba[i * 4 + c]]++;
    }
  }
  if (seedCount == 0) return null;
  // Fill colour: per-channel median of the seed (lettering is a minority of it).
  final fill = [
    for (var c = 0; c < 3; c++)
      () {
        var acc = 0;
        for (var v = 0; v < 256; v++) {
          acc += hist[c][v];
          if (acc * 2 >= seedCount) return v;
        }
        return 255;
      }(),
  ];
  bool near(int i) {
    for (var c = 0; c < 3; c++) {
      if ((rgba[i * 4 + c] - fill[c]).abs() > 48) return false;
    }
    return true;
  }

  // Seeds are the light labelled pixels (lettering comes back with the holes).
  final owner = Uint8List(n); // 0 free, 1 mine, 2 another balloon's
  final queue = <int>[];
  for (var i = 0; i < n; i++) {
    if (seed[i] == 0 || !near(i)) continue;
    owner[i] = seed[i];
    queue.add(i);
  }

  // Breadth-first from every seed at once: first to arrive claims the pixel, so
  // where two balloons join with no outline between them the split falls at the join.
  for (var q = 0; q < queue.length; q++) {
    final i = queue[q], x = i % w, y = i ~/ w, o = owner[i];
    for (final j in [
      if (x > 0) i - 1,
      if (x < w - 1) i + 1,
      if (y > 0) i - w,
      if (y < h - 1) i + w,
    ]) {
      if (owner[j] == 0 && near(j)) {
        owner[j] = o;
        queue.add(j);
      }
    }
  }
  // Cut thin necks: a balloon touching a white panel frame or gutter would run
  // along it. Erode by `outline` px, keep what stays joined to the label, grow
  // it back inside the fill: lines thinner than ~2 outlines fall away, the
  // balloon's body doesn't (a thin tail loses its far tip, as before).
  // Lettering counts as inside (holes in the fill), or dense small type breaks
  // the eroded body into pieces.
  final solidFill = Uint8List(n), out0 = Uint8List(n), st = <int>[];
  void reachOut(int i) {
    if (owner[i] != 1 && out0[i] == 0) {
      out0[i] = 1;
      st.add(i);
    }
  }

  for (var x = 0; x < w; x++) {
    reachOut(x);
    reachOut((h - 1) * w + x);
  }
  for (var y = 0; y < h; y++) {
    reachOut(y * w);
    reachOut(y * w + w - 1);
  }
  while (st.isNotEmpty) {
    final i = st.removeLast(), x = i % w, y = i ~/ w;
    if (x > 0) reachOut(i - 1);
    if (x < w - 1) reachOut(i + 1);
    if (y > 0) reachOut(i - w);
    if (y < h - 1) reachOut(i + w);
  }
  for (var i = 0; i < n; i++) {
    if (out0[i] == 0) solidFill[i] = 1;
  }
  var body = Uint8List.fromList(solidFill);
  for (var s = 0; s < outline; s++) {
    final next = Uint8List.fromList(body);
    for (var i = 0; i < n; i++) {
      if (body[i] == 0) continue;
      final x = i % w, y = i ~/ w;
      if (x == 0 ||
          x == w - 1 ||
          y == 0 ||
          y == h - 1 ||
          body[i - 1] == 0 ||
          body[i + 1] == 0 ||
          body[i - w] == 0 ||
          body[i + w] == 0) {
        next[i] = 0;
      }
    }
    body = next;
  }
  final kept = Uint8List(n), reach = <int>[];
  for (var i = 0; i < n; i++) {
    if (body[i] == 1 && seed[i] == 1) {
      kept[i] = 1;
      reach.add(i);
    }
  }
  for (var q = 0; q < reach.length; q++) {
    final i = reach[q], x = i % w, y = i ~/ w;
    for (final j in [
      if (x > 0) i - 1,
      if (x < w - 1) i + 1,
      if (y > 0) i - w,
      if (y < h - 1) i + w,
    ]) {
      if (body[j] == 1 && kept[j] == 0) {
        kept[j] = 1;
        reach.add(j);
      }
    }
  }
  // Grow back by `outline` steps, only over this balloon's fill.
  final dist = Int32List(n)..fillRange(0, n, -1);
  final back = <int>[];
  for (var i = 0; i < n; i++) {
    if (kept[i] == 1) {
      dist[i] = 0;
      back.add(i);
    }
  }
  for (var q = 0; q < back.length; q++) {
    final i = back[q], x = i % w, y = i ~/ w;
    if (dist[i] >= outline) continue;
    for (final j in [
      if (x > 0) i - 1,
      if (x < w - 1) i + 1,
      if (y > 0) i - w,
      if (y < h - 1) i + w,
    ]) {
      if (solidFill[j] == 1 && dist[j] < 0) {
        dist[j] = dist[i] + 1;
        back.add(j);
      }
    }
  }
  var grown = Uint8List(n);
  var count = 0;
  for (var i = 0; i < n; i++) {
    if (dist[i] >= 0) {
      grown[i] = 1;
      count++;
    }
  }
  // Ran on into the background (the fill reaches the crop's border, which the
  // caller leaves well clear of the balloon; the page's own edge doesn't
  // count), or the fill colour didn't hold (a textured caption box): use the
  // stored label as is. Size alone says nothing: short lettering ("UK")
  // labels a sliver of a big balloon (audit 2026-10-12: 32 of 64 flagged
  // balloons were thrown away by a 1.6x-of-label cap).
  // Reaching two opposite sides is a leak too: a balloon fits in its crop.
  var edge = 0, border = 0;
  bool side(bool page, int from, int step, int len) {
    if (page) return false;
    border += len;
    var on = 0;
    for (var k = 0; k < len; k++) {
      if (grown[from + k * step] == 1) on++;
    }
    edge += on;
    return on > 0;
  }

  final top = side(pageEdges.top, 0, 1, w);
  final bottom = side(pageEdges.bottom, (h - 1) * w, 1, w);
  final left = side(pageEdges.left, 0, w, h);
  final right = side(pageEdges.right, w - 1, w, h);
  final leaked =
      (border > 0 && edge > 0.05 * border) ||
      (top && bottom) ||
      (left && right);
  if (leaked && tight != null) {
    // Off-white paper the colour of the gutters: the fill runs off along them.
    // Cut this balloon the way it was cut before 2026-10-12, on the [tight]
    // region (x, y, w, h on this crop) around the detector box, where the
    // crop's edge bounds the run-off.
    final (tx0, ty0, tw0, th0) = tight;
    final tx = tx0.clamp(0, w - 1), ty = ty0.clamp(0, h - 1);
    final tw = math.min(tw0, w - tx), th = math.min(th0, h - ty);
    final subRgba = Uint8List(tw * th * 4), subSeed = Uint8List(tw * th);
    for (var y = 0; y < th; y++) {
      subRgba.setRange(
        y * tw * 4,
        (y + 1) * tw * 4,
        rgba,
        ((ty + y) * w + tx) * 4,
      );
      subSeed.setRange(y * tw, (y + 1) * tw, seed, (ty + y) * w + tx);
    }
    final sub = _legacyCutout(subRgba, tw, th, subSeed, outline: outline);
    if (sub == null) return null;
    final out = Uint8List(n);
    for (var y = 0; y < th; y++) {
      out.setRange((ty + y) * w + tx, (ty + y) * w + tx + tw, sub, y * tw);
    }
    return out;
  }
  if (leaked || count < seedCount * 0.5) {
    grown = Uint8List.fromList([for (final v in seed) v == 1 ? 1 : 0]);
  }

  // Take in the outline: grow by `outline` px (4-neighbour steps), never over
  // fill another balloon claimed.
  var cur = grown;
  for (var s = 0; s < outline; s++) {
    final next = Uint8List.fromList(cur);
    void take(int j) {
      if (owner[j] != 2) next[j] = 1;
    }

    for (var i = 0; i < n; i++) {
      if (cur[i] == 0) continue;
      final x = i % w, y = i ~/ w;
      if (x > 0) take(i - 1);
      if (x < w - 1) take(i + 1);
      if (y > 0) take(i - w);
      if (y < h - 1) take(i + w);
    }
    cur = next;
  }

  // Fill the lettering: whatever the outside can't reach from the border is balloon.
  final outside = Uint8List(n);
  final stack = <int>[];
  void seedOut(int i) {
    if (cur[i] == 0 && outside[i] == 0) {
      outside[i] = 1;
      stack.add(i);
    }
  }

  for (var x = 0; x < w; x++) {
    seedOut(x);
    seedOut((h - 1) * w + x);
  }
  for (var y = 0; y < h; y++) {
    seedOut(y * w);
    seedOut(y * w + w - 1);
  }
  while (stack.isNotEmpty) {
    final i = stack.removeLast(), x = i % w, y = i ~/ w;
    if (x > 0) seedOut(i - 1);
    if (x < w - 1) seedOut(i + 1);
    if (y > 0) seedOut(i - w);
    if (y < h - 1) seedOut(i + w);
  }

  // Feather 1 px (3x3 box) so the scaled-up edge isn't a staircase.
  final solid = Uint16List(n);
  for (var i = 0; i < n; i++) {
    solid[i] = outside[i] == 0 ? 255 : 0;
  }
  final rows = Uint16List(n), out = Uint8List(n);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = y * w + x;
      rows[i] =
          (solid[i] +
              (x > 0 ? solid[i - 1] : solid[i]) +
              (x < w - 1 ? solid[i + 1] : solid[i])) ~/
          3;
    }
  }
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = y * w + x;
      out[i] =
          (rows[i] +
              (y > 0 ? rows[i - w] : rows[i]) +
              (y < h - 1 ? rows[i + w] : rows[i])) ~/
          3;
    }
  }
  return out;
}

/// [balloonCutout] as it was before 2026-10-12: the fill may grow to 1.6x
/// the label, else the label is used. Kept for crops where the fill leaks.
Uint8List? _legacyCutout(
  Uint8List rgba,
  int w,
  int h,
  Uint8List seed, {
  required int outline,
}) {
  final n = w * h;
  final hist = List.generate(3, (_) => List<int>.filled(256, 0));
  var seedCount = 0;
  for (var i = 0; i < n; i++) {
    if (seed[i] != 1) continue;
    seedCount++;
    for (var c = 0; c < 3; c++) {
      hist[c][rgba[i * 4 + c]]++;
    }
  }
  if (seedCount == 0) return null;
  // Fill colour: per-channel median of the seed (lettering is a minority of it).
  final fill = [
    for (var c = 0; c < 3; c++)
      () {
        var acc = 0;
        for (var v = 0; v < 256; v++) {
          acc += hist[c][v];
          if (acc * 2 >= seedCount) return v;
        }
        return 255;
      }(),
  ];
  bool near(int i) {
    for (var c = 0; c < 3; c++) {
      if ((rgba[i * 4 + c] - fill[c]).abs() > 48) return false;
    }
    return true;
  }

  // Seeds are the light labelled pixels (lettering comes back with the holes).
  final owner = Uint8List(n); // 0 free, 1 mine, 2 another balloon's
  final queue = <int>[];
  for (var i = 0; i < n; i++) {
    if (seed[i] == 0 || !near(i)) continue;
    owner[i] = seed[i];
    queue.add(i);
  }

  // Breadth-first from every seed at once: first to arrive claims the pixel, so
  // where two balloons join with no outline between them the split falls at the join.
  for (var q = 0; q < queue.length; q++) {
    final i = queue[q], x = i % w, y = i ~/ w, o = owner[i];
    for (final j in [
      if (x > 0) i - 1,
      if (x < w - 1) i + 1,
      if (y > 0) i - w,
      if (y < h - 1) i + w,
    ]) {
      if (owner[j] == 0 && near(j)) {
        owner[j] = o;
        queue.add(j);
      }
    }
  }
  var grown = Uint8List(n);
  var count = 0;
  for (var i = 0; i < n; i++) {
    if (owner[i] == 1) {
      grown[i] = 1;
      count++;
    }
  }
  // Ran on into the background, or the fill colour didn't hold (a textured
  // caption box): use the stored label as is.
  if (count > seedCount * 1.6 || count < seedCount * 0.5) {
    grown = Uint8List.fromList([for (final v in seed) v == 1 ? 1 : 0]);
  }

  // Take in the outline: grow by `outline` px (4-neighbour steps), never over
  // fill another balloon claimed.
  var cur = grown;
  for (var s = 0; s < outline; s++) {
    final next = Uint8List.fromList(cur);
    void take(int j) {
      if (owner[j] != 2) next[j] = 1;
    }

    for (var i = 0; i < n; i++) {
      if (cur[i] == 0) continue;
      final x = i % w, y = i ~/ w;
      if (x > 0) take(i - 1);
      if (x < w - 1) take(i + 1);
      if (y > 0) take(i - w);
      if (y < h - 1) take(i + w);
    }
    cur = next;
  }

  // Fill the lettering: whatever the outside can't reach from the border is balloon.
  final outside = Uint8List(n);
  final stack = <int>[];
  void seedOut(int i) {
    if (cur[i] == 0 && outside[i] == 0) {
      outside[i] = 1;
      stack.add(i);
    }
  }

  for (var x = 0; x < w; x++) {
    seedOut(x);
    seedOut((h - 1) * w + x);
  }
  for (var y = 0; y < h; y++) {
    seedOut(y * w);
    seedOut(y * w + w - 1);
  }
  while (stack.isNotEmpty) {
    final i = stack.removeLast(), x = i % w, y = i ~/ w;
    if (x > 0) seedOut(i - 1);
    if (x < w - 1) seedOut(i + 1);
    if (y > 0) seedOut(i - w);
    if (y < h - 1) seedOut(i + w);
  }

  // Feather 1 px (3x3 box) so the scaled-up edge isn't a staircase.
  final solid = Uint16List(n);
  for (var i = 0; i < n; i++) {
    solid[i] = outside[i] == 0 ? 255 : 0;
  }
  final rows = Uint16List(n), out = Uint8List(n);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = y * w + x;
      rows[i] =
          (solid[i] +
              (x > 0 ? solid[i - 1] : solid[i]) +
              (x < w - 1 ? solid[i + 1] : solid[i])) ~/
          3;
    }
  }
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = y * w + x;
      out[i] =
          (rows[i] +
              (y > 0 ? rows[i - w] : rows[i]) +
              (y < h - 1 ? rows[i + w] : rows[i])) ~/
          3;
    }
  }
  return out;
}

/// The crop used when a balloon has no outline: its rect plus max(12 %, 12 px), on the page.
ui.Rect paddedBubbleRect(Bubble b, PageBubbles pb) {
  final pad = math.max(b.rect.height * 0.12, 12.0);
  return ui.Rect.fromLTRB(
    math.max(0, b.rect.left - pad),
    math.max(0, b.rect.top - pad),
    math.min(pb.width.toDouble(), b.rect.right + pad),
    math.min(pb.height.toDouble(), b.rect.bottom + pad),
  );
}

/// A balloon's cut-out: white with the balloon's alpha, covering [pageRect] (page px).
/// [tail] is the tip of its tail in page px, when it has one; [joined] holds
/// the labels of balloons it runs straight into (a chain).
class BubbleMask {
  final ui.Image image;
  final ui.Rect pageRect;
  final ui.Offset? tail;
  final Set<int> joined;
  const BubbleMask(
    this.image,
    this.pageRect, {
    this.tail,
    this.joined = const {},
  });
}

/// Whether cut-outs [a] (crop [ab]) and [b] (crop [bb]) are one chain: the
/// balloon fill ([page] light, [pw] wide) runs unbroken from a into b along at
/// least [minContact] px. [balloonCutout] splits a chain at the join, and both
/// sides may claim the neck; where one balloon merely overlaps another, the
/// strip both claim is its ink outline, which the fill never crosses.
bool cutoutsTouch(
  Uint8List a,
  (int, int, int, int) ab,
  Uint8List b,
  (int, int, int, int) bb,
  Uint8List page,
  int pw, {
  int minContact = 3,
}) {
  final (al, at, aw, ah) = ab;
  final (bl, bt, bw, bh) = bb;
  // Crops that don't meet can't hold a join; else walk both crops.
  if (al > bl + bw || bl > al + aw || at > bt + bh || bt > at + ah) {
    return false;
  }
  final x0 = math.min(al, bl), x1 = math.max(al + aw, bl + bw);
  final y0 = math.min(at, bt), y1 = math.max(at + ah, bt + bh);
  final ww = x1 - x0;
  bool inA(int x, int y) {
    final ax = x - al, ay = y - at;
    return ax >= 0 && ay >= 0 && ax < aw && ay < ah && a[ay * aw + ax] >= 128;
  }

  bool inB(int x, int y) {
    final bx = x - bl, by = y - bt;
    return bx >= 0 && by >= 0 && bx < bw && by < bh && b[by * bw + bx] >= 128;
  }

  bool light(int x, int y) {
    final o = (y * pw + x) * 4;
    return page[o] + page[o + 1] + page[o + 2] >= 3 * 160;
  }

  // Walk the fill from a's own pixels, through any strip both claim; count
  // b's own pixels reached.
  final seen = Uint8List(ww * (y1 - y0));
  final stack = <int>[];
  for (var y = y0; y < y1; y++) {
    for (var x = x0; x < x1; x++) {
      if (inA(x, y) && !inB(x, y) && light(x, y)) {
        seen[(y - y0) * ww + x - x0] = 1;
        stack.add((y - y0) * ww + x - x0);
      }
    }
  }
  var contact = 0;
  while (stack.isNotEmpty) {
    final i = stack.removeLast(), x = x0 + i % ww, y = y0 + i ~/ ww;
    for (final (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)]) {
      if (nx < x0 || ny < y0 || nx >= x1 || ny >= y1) continue;
      final j = (ny - y0) * ww + nx - x0;
      if (seen[j] == 1 || !inB(nx, ny) || !light(nx, ny)) continue;
      seen[j] = 1;
      if (!inA(nx, ny)) {
        if (++contact >= minContact) return true;
      } else {
        stack.add(j);
      }
    }
  }
  return false;
}

/// The tip of a balloon's tail in [alpha] ([w] x [h]), or null when it has none.
/// Rolling a disc of half the body's inscribed radius around the inside keeps
/// the body and drops thin protrusions; the tip is the point farthest past
/// what the disc reached, when that is over [minLen] radii out. Corners (of a
/// caption, or of a balloon cut off by a panel edge) stick out only ~0.4, and
/// thin tails often lose their tip in the cut-out, so the bar is low.
ui.Offset? tailTip(Uint8List alpha, int w, int h, {double minLen = 0.5}) {
  final n = w * h;
  const far = 1e9;
  final inside = Float64List(n);
  for (var i = 0; i < n; i++) {
    inside[i] = alpha[i] >= 128 ? far : 0;
  }
  _chamfer(inside, w, h, edgeIsZero: true);
  var rIn = 0.0;
  for (var i = 0; i < n; i++) {
    rIn = math.max(rIn, inside[i]);
  }
  final r = rIn / 2;
  if (r < 3) return null;
  final fromBody = Float64List(n);
  for (var i = 0; i < n; i++) {
    fromBody[i] = inside[i] > r ? 0 : far;
  }
  _chamfer(fromBody, w, h);
  var best = 0.0, at = -1;
  for (var i = 0; i < n; i++) {
    if (alpha[i] >= 128 && fromBody[i] > best) {
      best = fromBody[i];
      at = i;
    }
  }
  if (at < 0 || best - r < minLen * r) return null;
  return ui.Offset(at % w + 0.5, at ~/ w + 0.5);
}

/// In-place 3-4 chamfer distance transform (px): zeros are the sources. With
/// [edgeIsZero], everything outside the grid counts as a source too.
void _chamfer(Float64List d, int w, int h, {bool edgeIsZero = false}) {
  final e = edgeIsZero ? 0.0 : 1e9;
  double at(int x, int y) =>
      x < 0 || y < 0 || x >= w || y >= h ? e : d[y * w + x];
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = y * w + x;
      d[i] = math.min(
        d[i],
        math.min(
          math.min(at(x - 1, y) + 3, at(x, y - 1) + 3),
          math.min(at(x - 1, y - 1) + 4, at(x + 1, y - 1) + 4),
        ),
      );
    }
  }
  for (var y = h - 1; y >= 0; y--) {
    for (var x = w - 1; x >= 0; x--) {
      final i = y * w + x;
      d[i] = math.min(
        d[i],
        math.min(
          math.min(at(x + 1, y) + 3, at(x, y + 1) + 3),
          math.min(at(x + 1, y + 1) + 4, at(x - 1, y + 1) + 4),
        ),
      );
    }
  }
  for (var i = 0; i < d.length; i++) {
    if (d[i] < 1e8) d[i] /= 3;
  }
}

typedef _Box = (int label, int left, int top, int bw, int bh);

List<Uint8List?> _alphas((Uint8List labels, int w, List<_Box> boxes) job) => [
  for (final b in job.$3)
    balloonAlpha(job.$1, job.$2, b.$2, b.$3, b.$4, b.$5, b.$1),
];

/// [balloonCutout]'s seed for balloon [label] on the crop ([l], [t], [bw] x
/// [bh] in page px) from the label image ([labels], [lw] x [lh]; [k] = label px
/// per page px): 1 = this balloon, 2 = another, 0 = none. The host job credits
/// each text line to whichever detector box holds its centre, so in a tight
/// chain a line's box can be painted into the neighbour's label. A label pixel
/// inside a different balloon's detector [boxes] ((label, x0, y0, x1, y1), page
/// px) is therefore not trusted; the competitive growth gives it to whichever
/// balloon actually reaches it.
Uint8List cutoutSeed(
  Uint8List labels,
  int lw,
  int lh,
  double k,
  int l,
  int t,
  int bw,
  int bh,
  int label,
  List<(int, int, int, int, int)> boxes,
) {
  final seed = Uint8List(bw * bh);
  for (var y = 0; y < bh; y++) {
    final py = t + y, ly = math.min(lh - 1, (py * k).floor());
    for (var x = 0; x < bw; x++) {
      final px = l + x;
      final v = labels[ly * lw + math.min(lw - 1, (px * k).floor())];
      if (v == 0) continue;
      var trusted = true;
      for (final (bl, x0, y0, x1, y1) in boxes) {
        if (bl != v && px >= x0 && px < x1 && py >= y0 && py < y1) {
          trusted = false;
          break;
        }
      }
      if (trusted) seed[y * bw + x] = v == label ? 1 : 2;
    }
  }
  return seed;
}

typedef _Cut = (
  Uint8List page,
  int pw,
  Uint8List labels,
  int lw,
  int lh,
  double k,
  List<_Box> crops,
  List<(int, int, int, int, int)> boxes,
  int outline,
  List<(int, int, int, int)> tights,
);

List<Uint8List?> _cutouts(_Cut job) {
  final (page, pw, labels, lw, lh, k, crops, boxes, outline, tights) = job;
  return [
    for (final (ci, (label, l, t, bw, bh)) in crops.indexed)
      () {
        final rgba = Uint8List(bw * bh * 4);
        for (var y = 0; y < bh; y++) {
          rgba.setRange(
            y * bw * 4,
            (y + 1) * bw * 4,
            page,
            ((t + y) * pw + l) * 4,
          );
        }
        final seed = cutoutSeed(labels, lw, lh, k, l, t, bw, bh, label, boxes);
        final ph = page.length ~/ (pw * 4);
        return balloonCutout(
          rgba,
          bw,
          bh,
          seed,
          outline: outline,
          pageEdges: (
            left: l == 0,
            top: t == 0,
            right: l + bw == pw,
            bottom: t + bh == ph,
          ),
          tight: tights[ci],
        );
      }(),
  ];
}

Future<ui.Image> _alphaImage(Uint8List a, int w, int h) {
  final px = Uint8List(w * h * 4);
  for (var j = 0; j < a.length; j++) {
    px[j * 4] = 255;
    px[j * 4 + 1] = 255;
    px[j * 4 + 2] = 255;
    px[j * 4 + 3] = a[j];
  }
  final done = Completer<ui.Image>();
  ui.decodeImageFromPixels(px, w, h, ui.PixelFormat.rgba8888, done.complete);
  return done.future;
}

/// Per-label masks for every outlined balloon on the page. With the decoded
/// [page] the cut-out is rebuilt at page resolution from the page itself
/// ([balloonCutout]); without it, the stored label is used (half resolution,
/// interior only). Balloons whose label has no pixels are absent (the overlay
/// falls back to a rounded rect).
Future<Map<int, BubbleMask>> buildBubbleMasks(
  PageBubbles pb, {
  ui.Image? page,
}) async {
  final png = pb.mask;
  if (png == null || pb.bubbles.isEmpty) return {};
  final codec = await ui.instantiateImageCodec(png);
  final frame = await codec.getNextFrame();
  final img = frame.image;
  final w = img.width, h = img.height;
  final rgba = (await img.toByteData(
    format: ui.ImageByteFormat.rawRgba,
  ))!.buffer.asUint8List();
  img.dispose();
  codec.dispose();
  final labels = Uint8List(w * h);
  for (var i = 0; i < labels.length; i++) {
    labels[i] = rgba[i * 4];
  }
  final k = w / pb.width; // page px -> mask px

  final out = <int, BubbleMask>{};
  if (page != null && page.width == pb.width && page.height == pb.height) {
    final pageRgba = (await page.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!.buffer.asUint8List();
    final outline = math.max(
      3,
      (pb.height / 600).round(),
    ); // balloon outlines are ~5 px on a 3,000 px page
    final boxes = <_Box>[];
    final tights = <(int, int, int, int)>[];
    for (final b in pb.bubbles) {
      // Room past the detector box: the box is often tight or off-centre (a
      // short line of lettering sits at one end of its balloon), and the crop
      // edge counts as a leak, so the whole balloon has to fit.
      final r = b.rect.inflate(
        6.0 + outline + 0.8 * math.max(b.rect.width, b.rect.height),
      );
      final l = r.left.floor().clamp(0, pb.width - 1);
      final t = r.top.floor().clamp(0, pb.height - 1);
      final rr = r.right.ceil().clamp(l + 1, pb.width);
      final bb = r.bottom.ceil().clamp(t + 1, pb.height);
      boxes.add((b.label, l, t, rr - l, bb - t));
      final tr = b.rect.inflate(
        6.0 + outline + 0.15 * math.min(b.rect.width, b.rect.height),
      );
      tights.add((
        tr.left.floor() - l,
        tr.top.floor() - t,
        tr.width.ceil(),
        tr.height.ceil(),
      ));
    }
    final detector = [
      for (final b in pb.bubbles)
        (
          b.label,
          b.rect.left.floor(),
          b.rect.top.floor(),
          b.rect.right.ceil(),
          b.rect.bottom.ceil(),
        ),
    ];
    final alphas = await compute(_cutouts, (
      pageRgba,
      pb.width,
      labels,
      w,
      h,
      k,
      boxes,
      detector,
      outline,
      tights,
    ));
    for (var i = 0; i < boxes.length; i++) {
      final a = alphas[i];
      if (a == null) continue;
      final (label, l, t, bw, bh) = boxes[i];
      final joined = {
        for (var j = 0; j < boxes.length; j++)
          if (j != i &&
              alphas[j] != null &&
              cutoutsTouch(
                a,
                (l, t, bw, bh),
                alphas[j]!,
                (boxes[j].$2, boxes[j].$3, boxes[j].$4, boxes[j].$5),
                pageRgba,
                pb.width,
                minContact: outline,
              ))
            boxes[j].$1,
      };
      var tip = tailTip(a, bw, bh);
      if (tip != null) tip += ui.Offset(l.toDouble(), t.toDouble());
      // A tip inside a neighbour's crop is the join between chained balloons.
      for (final (ol, x, y, ow, oh) in boxes) {
        if (tip != null &&
            ol != label &&
            tip.dx >= x &&
            tip.dx < x + ow &&
            tip.dy >= y &&
            tip.dy < y + oh) {
          tip = null;
        }
      }
      out[label] = BubbleMask(
        await _alphaImage(a, bw, bh),
        ui.Rect.fromLTWH(
          l.toDouble(),
          t.toDouble(),
          bw.toDouble(),
          bh.toDouble(),
        ),
        tail: tip,
        joined: joined,
      );
    }
    return out;
  }

  final boxes = <_Box>[];
  for (final b in pb.bubbles) {
    final r = b.rect.inflate(6);
    final l = (r.left * k).floor().clamp(0, w - 1);
    final t = (r.top * k).floor().clamp(0, h - 1);
    final rr = (r.right * k).ceil().clamp(l + 1, w);
    final bb = (r.bottom * k).ceil().clamp(t + 1, h);
    boxes.add((b.label, l, t, rr - l, bb - t));
  }
  final alphas = await compute(_alphas, (labels, w, boxes));
  for (var i = 0; i < boxes.length; i++) {
    final a = alphas[i];
    if (a == null) continue;
    final (label, l, t, bw, bh) = boxes[i];
    out[label] = BubbleMask(
      await _alphaImage(a, bw, bh),
      ui.Rect.fromLTRB(l / k, t / k, (l + bw) / k, (t + bh) / k),
    );
  }
  return out;
}

/// [pb]'s balloons as reading steps: each chain of joined balloons ([masks]'
/// `joined`) is one step, at its first balloon's place in the reading order,
/// its balloons in reading order. Without masks every balloon is its own step.
List<List<Bubble>> bubbleGroups(PageBubbles pb, Map<int, BubbleMask>? masks) {
  final groupOf = <int, List<Bubble>>{};
  final groups = <List<Bubble>>[];
  for (final b in pb.bubbles) {
    final joined = masks?[b.label]?.joined ?? const <int>{};
    // ponytail: joins are pairwise; a chain whose members only meet through a
    // later balloon splits in two. Union-find if long chains show up.
    final g = joined.map((l) => groupOf[l]).nonNulls.firstOrNull;
    if (g == null) {
      groups.add([b]);
      groupOf[b.label] = groups.last;
    } else {
      g.add(b);
      groupOf[b.label] = g;
    }
  }
  return groups;
}
