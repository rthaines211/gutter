import 'dart:typed_data';
import 'dart:ui';
import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:comic_reader_app/models/page_bubbles.dart';
import 'package:comic_reader_app/services/bubble_mask.dart';

/// 12x12 label image: label 5 is a ring (outline of a 8x8 square at 2..9) with an
/// unlabelled hole inside — like a balloon whose lettering isn't part of the fill.
Uint8List ringImage() {
  final px = Uint8List(12 * 12);
  for (var y = 2; y <= 9; y++) {
    for (var x = 2; x <= 9; x++) {
      if (x == 2 || x == 9 || y == 2 || y == 9) px[y * 12 + x] = 5;
    }
  }
  return px;
}

void main() {
  test('fills the hole', () {
    final a = balloonAlpha(ringImage(), 12, 0, 0, 12, 12, 5, grow: 0)!;
    expect(
      a[5 * 12 + 5],
      255,
      reason: 'inside the ring is part of the balloon',
    );
    expect(a[0], 0, reason: 'outside stays transparent');
  });

  test('grows the outline by `grow` px', () {
    final a = balloonAlpha(ringImage(), 12, 0, 0, 12, 12, 5, grow: 2)!;
    expect(a[0 * 12 + 0], 255);
    expect(a[0 * 12 + 11], 255);
    final tight = balloonAlpha(ringImage(), 12, 0, 0, 12, 12, 5, grow: 1)!;
    expect(tight[0], 0);
    expect(tight[1 * 12 + 1], 255);
  });

  test('respects the box offset', () {
    final a = balloonAlpha(ringImage(), 12, 2, 2, 8, 8, 5, grow: 0)!;
    expect(a.length, 64);
    expect(a[0], 255);
    expect(a[3 * 8 + 3], 255);
  });

  test('null when the label is absent', () {
    expect(balloonAlpha(ringImage(), 12, 0, 0, 12, 12, 7), isNull);
  });

  test('padded fallback rect stays on the page', () {
    final pb = PageBubbles.fromJson({
      'v': 1,
      'w': 100,
      'h': 100,
      'bubbles': [
        {
          'r': [5, 5, 20, 50],
          'label': 1,
        },
      ],
    });
    expect(
      paddedBubbleRect(pb.bubbles.first, pb),
      const Rect.fromLTRB(0, 0, 37, 67),
    );
  });

  group('balloonCutout', () {
    const w = 60;
    int at(Uint8List a, int x, int y) => a[y * w + x];

    test(
      'fills the notch, takes in the outline and the lettering, leaves the background',
      () {
        final c = balloonCrop();
        final a = balloonCutout(c.rgba, w, 40, c.seed, outline: 3)!;
        expect(
          at(a, 50, 20),
          255,
          reason: 'notch on the right edge, inside the balloon',
        );
        expect(at(a, 30, 7), greaterThan(200), reason: 'top outline');
        expect(at(a, 29, 19), 255, reason: 'letter');
        expect(at(a, 1, 1), 0, reason: 'background corner');
        expect(at(a, 58, 20), 0, reason: 'background beside the balloon');
      },
    );

    test(
      'a light background does not swallow the crop: falls back to the stored region',
      () {
        final c = balloonCrop(whiteBackground: true);
        final a = balloonCutout(c.rgba, w, 40, c.seed, outline: 3)!;
        expect(at(a, 1, 1), 0);
        expect(at(a, 30, 20), 255);
      },
    );

    test('a balloon much bigger than its label is still cut whole', () {
      // Short lettering ("UK", "HMM") labels a sliver of a big balloon: the
      // fill grows to many times the label and is still the balloon.
      final c = balloonCrop();
      final seed = Uint8List(w * 40);
      for (var y = 17; y <= 23; y++) {
        for (var x = 24; x <= 36; x++) {
          seed[y * w + x] = c.seed[y * w + x];
        }
      }
      final a = balloonCutout(c.rgba, w, 40, seed, outline: 3)!;
      expect(at(a, 50, 20), 255, reason: 'far side of the balloon');
      expect(at(a, 30, 9), 255, reason: 'top of the balloon');
      expect(at(a, 1, 1), 0, reason: 'background corner');
    });

    test('a thin white gutter touching the balloon is not taken in', () {
      // A 3 px white panel frame crosses the crop and touches the balloon.
      final c = balloonCrop();
      final rgba = Uint8List.fromList(c.rgba);
      for (var y = 32; y <= 34; y++) {
        for (var x = 0; x < w; x++) {
          rgba.setAll((y * w + x) * 4, [255, 255, 255, 255]);
        }
      }
      final a = balloonCutout(rgba, w, 40, c.seed, outline: 3)!;
      expect(at(a, 50, 20), 255, reason: 'the balloon is still whole');
      expect(at(a, 2, 33), 0, reason: 'the gutter far from the balloon');
      expect(at(a, 57, 33), 0, reason: 'the gutter on the other side');
    });

    test('a balloon cut off by the page edge is not a leak', () {
      // The page ends at the crop's left side, mid-balloon.
      final c = balloonCrop();
      const cut = 12;
      final rgba = Uint8List.fromList(c.rgba), seed = Uint8List(w * 40);
      for (var y = 0; y < 40; y++) {
        for (var x = 0; x < w; x++) {
          final src = y * w + (x + cut < w - 1 ? x + cut : w - 1);
          rgba.setRange((y * w + x) * 4, (y * w + x) * 4 + 4, c.rgba, src * 4);
          if (x < w - cut) seed[y * w + x] = c.seed[src];
        }
      }
      final a = balloonCutout(
        rgba,
        w,
        40,
        seed,
        outline: 3,
        pageEdges: (left: true, top: false, right: false, bottom: false),
      )!;
      expect(at(a, 2, 20), 255, reason: 'balloon running off the page');
      expect(at(a, 30, 3), 0, reason: 'background above');
    });

    test('on a light background, the tight region bounds the run-off', () {
      final c = balloonCrop(whiteBackground: true);
      final a = balloonCutout(
        c.rgba,
        w,
        40,
        c.seed,
        outline: 3,
        tight: (4, 4, 52, 32),
      )!;
      expect(at(a, 50, 20), 255, reason: 'the notch, inside the tight region');
      expect(at(a, 1, 1), 0, reason: 'background outside it');
    });

    test("a neighbour's balloon outside my outline stays out", () {
      final c = balloonCrop(whiteBackground: true);
      final seed = Uint8List.fromList(c.seed);
      for (var y = 0; y < 40; y++) {
        for (var x = 0; x < w; x++) {
          // everything outside the ellipse's outline belongs to a neighbour
          final d =
              ((x - 30) * (x - 30)) / (24 * 24) +
              ((y - 20) * (y - 20)) / (14 * 14);
          if (d > 1.0) seed[y * w + x] = 2;
        }
      }
      final a = balloonCutout(c.rgba, w, 40, seed, outline: 0)!;
      expect(at(a, 1, 1), 0);
      expect(at(a, 58, 20), 0);
      expect(at(a, 50, 20), 255, reason: 'my notch, inside my outline');
    });

    test('two balloons joined by a neck split at the join', () {
      // 80x30 white "peanut": two round lobes joined by a white neck, on green.
      // Labels miss parts of a balloon, like the host job's.
      const w = 80, h = 30;
      final rgba = Uint8List(w * h * 4), seed = Uint8List(w * h);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final inLeft = (x - 20) * (x - 20) + (y - 15) * (y - 15) <= 13 * 13;
          final inRight = (x - 60) * (x - 60) + (y - 15) * (y - 15) <= 13 * 13;
          final inNeck = x >= 30 && x <= 50 && y >= 12 && y <= 18;
          final white = inLeft || inRight || inNeck;
          rgba.setAll(
            (y * w + x) * 4,
            white ? [255, 255, 255, 255] : [60, 140, 60, 255],
          );
          if ((x - 20) * (x - 20) + (y - 15) * (y - 15) <= 12 * 12) {
            seed[y * w + x] = 1;
          }
          // The neighbour's label misses the half of its lobe nearest the join.
          if (x >= 60 && (x - 60) * (x - 60) + (y - 15) * (y - 15) <= 12 * 12) {
            seed[y * w + x] = 2;
          }
        }
      }
      final a = balloonCutout(rgba, w, h, seed, outline: 0)!;
      expect(a[15 * w + 20], 255, reason: 'my lobe');
      expect(a[15 * w + 33], 255, reason: 'my side of the neck');
      expect(a[15 * w + 55], 0, reason: "the other lobe's unlabelled half");
    });

    test('null when there is no seed', () {
      final c = balloonCrop();
      expect(
        balloonCutout(c.rgba, w, 40, Uint8List(w * 40), outline: 3),
        isNull,
      );
    });
  });

  testWidgets('buildBubbleMasks cuts from the page image when it has one', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final c = balloonCrop();
      // Label PNG at half resolution, like the host job's: the seed, label 1.
      final lab = img.Image(width: 30, height: 20, numChannels: 1);
      for (var y = 0; y < 20; y++) {
        for (var x = 0; x < 30; x++) {
          lab.setPixelR(x, y, c.seed[(y * 2) * 60 + x * 2]);
        }
      }
      final pb = PageBubbles(
        width: 60,
        height: 40,
        bubbles: [const Bubble(Rect.fromLTWH(10, 8, 40, 24), 1)],
        mask: Uint8List.fromList(img.encodePng(lab)),
      );
      final done = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        c.rgba,
        60,
        40,
        ui.PixelFormat.rgba8888,
        done.complete,
      );
      final page = await done.future;

      Future<int> notchAlpha(Map<int, BubbleMask> masks) async {
        final m = masks[1]!;
        final px = (await m.image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        final sx =
            m.image.width /
            m.pageRect.width; // label-only masks are half resolution
        final x = ((50 - m.pageRect.left) * sx).floor(),
            y = ((20 - m.pageRect.top) * sx).floor();
        return px.getUint8((y * m.image.width + x) * 4 + 3);
      }

      final stored = (await buildBubbleMasks(pb))[1]!;
      expect(
        stored.image.width,
        lessThan(stored.pageRect.width),
        reason: 'label only: half resolution',
      );
      final cut = await buildBubbleMasks(pb, page: page);
      expect(
        cut[1]!.image.width,
        cut[1]!.pageRect.width,
        reason: 'cut at page resolution',
      );
      expect(await notchAlpha(cut), 255, reason: 'notch filled from the page');
    });
  });

  group('cutoutSeed', () {
    // Label image 20x10 at the page's resolution (k = 1). Balloon 1 owns the
    // left half, balloon 2 the right half, and the host job also painted a stray
    // text-line box of label 1 at x 12..15, inside balloon 2's detector box.
    final labels = Uint8List(20 * 10);
    for (var y = 0; y < 10; y++) {
      for (var x = 0; x < 20; x++) {
        labels[y * 20 + x] = x < 10 ? 1 : 2;
        if (x >= 12 && x <= 15 && y >= 3 && y <= 5) labels[y * 20 + x] = 1;
      }
    }
    const boxes = [(1, 0, 0, 10, 10), (2, 10, 0, 20, 10)];

    test("a label inside another balloon's box is not a seed", () {
      final seed = cutoutSeed(labels, 20, 10, 1.0, 0, 0, 20, 10, 2, boxes);
      expect(
        seed[4 * 20 + 13],
        0,
        reason: "label 1's stray box inside balloon 2's box",
      );
      expect(seed[4 * 20 + 17], 1, reason: 'my own label in my box');
      expect(seed[4 * 20 + 3], 2, reason: 'the neighbour in its own box');
    });

    test('crops and scales from page to label pixels', () {
      final seed = cutoutSeed(labels, 20, 10, 0.5, 0, 0, 40, 20, 1, const []);
      expect(seed.length, 40 * 20);
      expect(seed[0], 1);
      expect(seed[39], 2);
    });
  });

  group('tailTip', () {
    // A 120 x 80 ellipse, optionally with a 6 px wide tail running 40 px down
    // from its bottom-left.
    Uint8List balloon({bool tail = false, bool box = false}) {
      const w = 160, h = 150;
      final a = Uint8List(w * h);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final dx = (x - 80) / 60, dy = (y - 50) / 40;
          final inBody = box
              ? x >= 20 && x < 140 && y >= 10 && y < 90
              : dx * dx + dy * dy <= 1;
          final inTail =
              tail && y >= 70 && y < 130 && (x - (60 - (y - 70) / 3)).abs() < 3;
          if (inBody || inTail) a[y * w + x] = 255;
        }
      }
      return a;
    }

    test('finds the tip of a tail', () {
      final tip = tailTip(balloon(tail: true), 160, 150)!;
      expect(tip.dy, greaterThan(120));
      expect(tip.dx, lessThan(50));
    });

    test('a plain balloon has none', () {
      expect(tailTip(balloon(), 160, 150), isNull);
    });

    test("a caption's corners are not tails", () {
      expect(tailTip(balloon(box: true), 160, 150), isNull);
    });
  });

  group('chains', () {
    // Two 20 x 20 balloons side by side on a white 40 x 20 page, each cut-out
    // claiming a 2 px strip in the middle: fill (a join) or ink (an overlap).
    (Uint8List, Uint8List, Uint8List) pair({required bool inkBetween}) {
      final page = Uint8List(40 * 20 * 4)..fillRange(0, 40 * 20 * 4, 255);
      if (inkBetween) {
        for (var y = 0; y < 20; y++) {
          for (final x in [19, 20]) {
            page.fillRange((y * 40 + x) * 4, (y * 40 + x) * 4 + 3, 0);
          }
        }
      }
      // a covers x 0..20, b covers x 19..39: they share x 19..20.
      final a = Uint8List(21 * 20)..fillRange(0, 21 * 20, 255);
      final b = Uint8List(21 * 20)..fillRange(0, 21 * 20, 255);
      return (a, b, page);
    }

    test('fill running across the join joins them', () {
      final (a, b, page) = pair(inkBetween: false);
      expect(
        cutoutsTouch(a, (0, 0, 21, 20), b, (19, 0, 21, 20), page, 40),
        isTrue,
      );
    });

    test('an outline between them is an overlap, not a join', () {
      final (a, b, page) = pair(inkBetween: true);
      expect(
        cutoutsTouch(a, (0, 0, 21, 20), b, (19, 0, 21, 20), page, 40),
        isFalse,
      );
    });

    test('bubbleGroups puts a chain at its first balloon', () async {
      final pb = PageBubbles(
        width: 10,
        height: 10,
        bubbles: [
          for (final l in [1, 2, 3, 4]) Bubble(Rect.fromLTWH(0, 0, 1, 1), l),
        ],
      );
      final img = await _blank();
      BubbleMask m(Set<int> j) => BubbleMask(img, Rect.zero, joined: j);
      final groups = bubbleGroups(pb, {
        1: m({}),
        2: m({4}),
        3: m({}),
        4: m({2}),
      });
      expect(
        [
          for (final g in groups) [for (final b in g) b.label],
        ],
        [
          [1],
          [2, 4],
          [3],
        ],
      );
      expect(bubbleGroups(pb, null).length, 4);
    });
  });
}

/// A 60x40 crop: green background, a white ellipse with a 2-px black outline,
/// and a black "letter" in the middle. The seed (label region) is the ellipse's
/// interior minus a notch on its right edge, like the host job's masks.
({Uint8List rgba, Uint8List seed}) balloonCrop({bool whiteBackground = false}) {
  const w = 60, h = 40;
  final rgba = Uint8List(w * h * 4);
  final seed = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final d =
          ((x - 30) * (x - 30)) / (24 * 24) + ((y - 20) * (y - 20)) / (14 * 14);
      var c = whiteBackground ? 255 : -1;
      if (d <= 1.0) c = 255;
      if (d > 0.85 && d <= 1.0) c = 0; // outline
      if (x >= 28 && x <= 31 && y >= 18 && y <= 21) c = 0; // a letter
      final i = (y * w + x) * 4;
      if (c < 0) {
        rgba.setAll(i, [60, 140, 60, 255]);
      } else {
        rgba.setAll(i, [c, c, c, 255]);
      }
      if (d <= 0.8 && !(x > 44 && y >= 17 && y <= 23)) {
        seed[y * w + x] = 1;
      }
    }
  }
  return (rgba: rgba, seed: seed);
}

Future<ui.Image> _blank() {
  final done = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    Uint8List(4),
    1,
    1,
    ui.PixelFormat.rgba8888,
    done.complete,
  );
  return done.future;
}
