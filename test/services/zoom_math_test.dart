import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:vector_math/vector_math_64.dart';
import 'package:comic_reader_app/services/zoom_math.dart';

void main() {
  group('zoomAroundPoint', () {
    test('returns identity when targetScale == 1', () {
      final m = zoomAroundPoint(
        imagePoint: const Offset(50, 50),
        targetScale: 1.0,
        viewport: const Size(400, 800),
        displayRect: const Rect.fromLTWH(0, 0, 400, 800),
      );
      expect(m, Matrix4.identity());
    });

    test('tap point stays under same screen coordinate after zoom', () {
      const tap = Offset(100, 200);
      final m = zoomAroundPoint(
        imagePoint: tap,
        targetScale: 2.5,
        viewport: const Size(400, 800),
        displayRect: const Rect.fromLTWH(0, 0, 400, 800),
      );
      final v = m.transform3(Vector3(tap.dx, tap.dy, 0));
      // No clamping is triggered at this tap location, so the post-transform
      // coordinate must land essentially exactly on the original tap.
      // Clamping is exercised separately by the "clamps translation..." test.
      expect(v.x, closeTo(tap.dx, 1.0));
      expect(v.y, closeTo(tap.dy, 1.0));
    });

    test('result scale equals targetScale', () {
      final m = zoomAroundPoint(
        imagePoint: const Offset(100, 200),
        targetScale: 2.5,
        viewport: const Size(400, 800),
        displayRect: const Rect.fromLTWH(0, 0, 400, 800),
      );
      expect(m.entry(0, 0), closeTo(2.5, 0.001));
      expect(m.entry(1, 1), closeTo(2.5, 0.001));
    });

    test('clamps translation so image edge does not enter viewport', () {
      // Tap at corner → without clamping, image would expose black on opposite side.
      final m = zoomAroundPoint(
        imagePoint: const Offset(0, 0),
        targetScale: 2.5,
        viewport: const Size(400, 800),
        displayRect: const Rect.fromLTWH(0, 0, 400, 800),
      );
      final tx = m.entry(0, 3);
      final ty = m.entry(1, 3);
      // Image right edge: 400 * 2.5 + tx = 1000 + tx. Must be >= 400.
      expect(1000 + tx, greaterThanOrEqualTo(400 - 1));
      // Image bottom edge: 800 * 2.5 + ty = 2000 + ty. Must be >= 800.
      expect(2000 + ty, greaterThanOrEqualTo(800 - 1));
    });

    test('handles offset displayRect (letterboxed image)', () {
      // 300×600 image letterboxed in a 400×800 viewport.
      // Tap at the top-left of the display rect. With scale=2.5:
      //   unclamped tx = -50 * 1.5 = -75
      //   correct clamp range: [-475, -125]  → clamps to -125
      //   buggy clamp range (ignoring displayRect.left): [-350, 0] → leaves -75 (no clamp)
      // So a displayRect.left bug would leave tx == -75 instead of -125.
      final m = zoomAroundPoint(
        imagePoint: const Offset(50, 100),
        targetScale: 2.5,
        viewport: const Size(400, 800),
        displayRect: const Rect.fromLTWH(50, 100, 300, 600),
      );
      expect(m.entry(0, 0), closeTo(2.5, 0.001));
      expect(m.entry(0, 3), closeTo(-125, 1.0));
      expect(m.entry(1, 3), closeTo(-250, 1.0));
    });
  });

  group('detectOverscroll', () {
    Matrix4 scaledAt(double scale, double tx, double ty) =>
        Matrix4.identity()
          ..setEntry(0, 0, scale)
          ..setEntry(1, 1, scale)
          ..setEntry(0, 3, tx)
          ..setEntry(1, 3, ty);

    test('returns null when not scaled', () {
      final result = detectOverscroll(
        transform: Matrix4.identity(),
        displayRect: const Rect.fromLTWH(0, 0, 400, 800),
        viewport: const Size(400, 800),
        velocity: const Offset(-500, 0),
      );
      expect(result, isNull);
    });

    test('returns null when velocity below threshold', () {
      final result = detectOverscroll(
        transform: scaledAt(2.0, -400, 0),
        displayRect: const Rect.fromLTWH(0, 0, 400, 800),
        viewport: const Size(400, 800),
        velocity: const Offset(-100, 0),
      );
      expect(result, isNull);
    });

    test('returns rightEdge at right edge with leftward velocity', () {
      // scale=2, viewport=400, scaled width=800, at right edge: tx = -400
      final result = detectOverscroll(
        transform: scaledAt(2.0, -400, 0),
        displayRect: const Rect.fromLTWH(0, 0, 400, 800),
        viewport: const Size(400, 800),
        velocity: const Offset(-500, 0),
      );
      expect(result, EdgeDirection.rightEdge);
    });

    test('returns null for a vertical-dominant fling at an edge', () {
      final result = detectOverscroll(
        transform: scaledAt(2.0, -400, 0),
        displayRect: const Rect.fromLTWH(0, 0, 400, 800),
        viewport: const Size(400, 800),
        velocity: const Offset(-400, -1500),
      );
      expect(result, isNull);
    });

    test('returns leftEdge at left edge with rightward velocity', () {
      final result = detectOverscroll(
        transform: scaledAt(2.0, 0, 0),
        displayRect: const Rect.fromLTWH(0, 0, 400, 800),
        viewport: const Size(400, 800),
        velocity: const Offset(500, 0),
      );
      expect(result, EdgeDirection.leftEdge);
    });

    test('returns null at middle position regardless of velocity', () {
      final result = detectOverscroll(
        transform: scaledAt(2.0, -200, 0),
        displayRect: const Rect.fromLTWH(0, 0, 400, 800),
        viewport: const Size(400, 800),
        velocity: const Offset(-500, 0),
      );
      expect(result, isNull);
    });

    test('honors displayRect.left when computing edges (offset rect)', () {
      // displayRect.left=50, scale=2 → imageLeftInView = 100 + tx.
      // Scaled width = 300 * 2 = 600 → imageRightInView = 700 + tx.
      // At tx = -250:
      //   correct:  imageRightInView = 450, NOT at right edge (viewport.width = 400)
      //   buggy:    imageRightInView would be 350 (if displayRect.left ignored), AT right edge
      // Leftward velocity above threshold. Correct behavior returns null;
      // a displayRect.left bug would return rightEdge.
      final result = detectOverscroll(
        transform: scaledAt(2.0, -250, 0),
        displayRect: const Rect.fromLTWH(50, 0, 300, 800),
        viewport: const Size(400, 800),
        velocity: const Offset(-500, 0),
      );
      expect(result, isNull);
    });
  });
}
