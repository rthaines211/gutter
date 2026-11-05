import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/services/page_transform_calculator.dart';

void main() {
  group('calculatePageTransforms', () {
    test('fitScreen portrait single page → identity', () {
      final transforms = calculatePageTransforms(
        containRect: const Rect.fromLTWH(50, 0, 300, 844),
        viewportSize: const Size(390, 844),
        isSpread: false,
        isPortrait: true,
        isRtl: false,
        fitMode: 'fitScreen',
      );
      expect(transforms.length, 1);
      expect(transforms[0], Matrix4.identity());
    });

    test('fitWidth portrait → zooms to fill width and chunks', () {
      // Contained: 300px wide in 390 viewport → scale = 1.3
      final transforms = calculatePageTransforms(
        containRect: const Rect.fromLTWH(50, 0, 300, 844),
        viewportSize: const Size(390, 844),
        isSpread: false,
        isPortrait: true,
        isRtl: false,
        fitMode: 'fitWidth',
      );
      expect(transforms.length, greaterThan(1));
      final scale = transforms[0].entry(0, 0);
      expect(scale, closeTo(1.3, 0.01));
    });

    test('fitHeight portrait when height already fills → identity', () {
      final transforms = calculatePageTransforms(
        containRect: const Rect.fromLTWH(50, 0, 300, 844),
        viewportSize: const Size(390, 844),
        isSpread: false,
        isPortrait: true,
        isRtl: false,
        fitMode: 'fitHeight',
      );
      expect(transforms.length, 1);
      expect(transforms[0], Matrix4.identity());
    });

    test('fitScreen landscape narrow page → auto-zoom to width', () {
      final transforms = calculatePageTransforms(
        containRect: const Rect.fromLTWH(300, 0, 424, 768),
        viewportSize: const Size(1024, 768),
        isSpread: false,
        isPortrait: false,
        isRtl: false,
        fitMode: 'fitScreen',
      );
      expect(transforms.length, greaterThan(1));
      final scale = transforms[0].entry(0, 0);
      expect(scale, closeTo(2.415, 0.01));
    });

    test('landscape spread → full view then grid cells', () {
      final transforms = calculatePageTransforms(
        containRect: const Rect.fromLTWH(0, 50, 1024, 668),
        viewportSize: const Size(1024, 768),
        isSpread: true,
        isPortrait: false,
        isRtl: false,
        fitMode: 'fitScreen',
      );
      // Full view + grid (at least 2 cols for half-width zoom)
      expect(transforms.length, greaterThan(2));
      expect(transforms[0], Matrix4.identity());
      // Grid cells should be zoomed ~2x (half-width fills viewport)
      expect(transforms[1].entry(0, 0), closeTo(2.0, 0.1));
    });

    test('portrait spread → full view, left half, right half', () {
      final transforms = calculatePageTransforms(
        containRect: const Rect.fromLTWH(0, 276, 390, 292),
        viewportSize: const Size(390, 844),
        isSpread: true,
        isPortrait: true,
        isRtl: false,
        fitMode: 'fitScreen',
      );
      expect(transforms.length, 3);
      expect(transforms[0], Matrix4.identity()); // full view
      expect(transforms[1].entry(0, 0), closeTo(2.0, 0.1)); // left half zoom
    });

    test('portrait spread RTL → full view, right half, left half', () {
      final transforms = calculatePageTransforms(
        containRect: const Rect.fromLTWH(0, 276, 390, 292),
        viewportSize: const Size(390, 844),
        isSpread: true,
        isPortrait: true,
        isRtl: true,
        fitMode: 'fitScreen',
      );
      expect(transforms.length, 3);
      expect(transforms[0], Matrix4.identity()); // full view
      // transforms[1] = right half, transforms[2] = left half
      final txSecond = transforms[1].entry(0, 3);
      final txThird = transforms[2].entry(0, 3);
      expect(txSecond, lessThan(txThird)); // right is more negative tx
    });

    test('portrait spread halves account for containRect.top offset', () {
      // Spread image: 800×400 in 390×844 viewport
      // containRect: image fills width, centered vertically
      // width=390, height=390*400/800=195, left=0, top=(844-195)/2=324.5
      final transforms = calculatePageTransforms(
        containRect: const Rect.fromLTWH(0, 324.5, 390, 195),
        viewportSize: const Size(390, 844),
        isSpread: true,
        isPortrait: true,
        isRtl: false,
        fitMode: 'fitScreen',
      );
      expect(transforms.length, 3);
      // Left half: zoom = 390 / 195 = 2.0
      final zoom = transforms[1].entry(0, 0);
      expect(zoom, closeTo(2.0, 0.01));
      // ty should center the scaled image, NOT show top-of-page
      // scaledHeight = 195 * 2 = 390
      // Correct ty = (844 - 390) / 2 - 324.5 * 2 = 227 - 649 = -422
      final ty = transforms[1].entry(1, 3);
      expect(ty, closeTo(-422.0, 1.0));
      // Verify left half tx = 0 (no left offset)
      final tx = transforms[1].entry(0, 3);
      expect(tx, closeTo(0.0, 0.01));
    });

    test('portrait spread halves fit entirely within viewport (no clipping)', () {
      // Tall spread: 390px wide × 600px tall in a 390×844 viewport
      // Half width = 195, zoom to fill width = 2.0
      // Scaled height = 600 * 2.0 = 1200 > 844 viewport
      // Old behavior: pins to top, clips bottom
      // New behavior: scale down so full half fits in viewport
      final transforms = calculatePageTransforms(
        containRect: const Rect.fromLTWH(0, 122, 390, 600),
        viewportSize: const Size(390, 844),
        isSpread: true,
        isPortrait: true,
        isRtl: false,
        fitMode: 'fitScreen',
      );
      expect(transforms.length, 3);
      // The zoom should be min(widthZoom, heightZoom)
      // widthZoom = 390 / 195 = 2.0
      // heightZoom = 844 / 600 = 1.4067
      // Should pick heightZoom since it's smaller
      final zoom = transforms[1].entry(0, 0);
      expect(zoom, closeTo(1.407, 0.01));
      // Scaled height should fit within viewport
      final scaledHeight = 600 * zoom;
      expect(scaledHeight, lessThanOrEqualTo(844.0));
    });
  });
}
