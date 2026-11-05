import 'package:flutter/material.dart';

/// Physical edge direction reported by overscroll detection.
/// The reader maps to advance/retreat based on reading direction.
enum EdgeDirection { leftEdge, rightEdge }

/// Velocity threshold for overscroll detection (pixels/second).
const double overscrollVelocityThreshold = 300.0;

/// Edge-detection tolerance in pixels.
const double _edgeEpsilon = 1.0;

/// Below this scale, a transform is treated as effectively un-zoomed
/// (identity for `zoomAroundPoint`, ignored by `detectOverscroll`).
const double _isScaledEpsilon = 1.01;

/// Computes a Matrix4 that zooms to [targetScale] keeping [imagePoint] under
/// the same screen coordinate. [imagePoint] is in viewport coordinates (where
/// the image actually renders inside [displayRect]). The result translation
/// is clamped so the scaled image edges don't cross viewport edges.
Matrix4 zoomAroundPoint({
  required Offset imagePoint,
  required double targetScale,
  required Size viewport,
  required Rect displayRect,
}) {
  if (targetScale <= _isScaledEpsilon) return Matrix4.identity();

  final tx = -imagePoint.dx * (targetScale - 1);
  final ty = -imagePoint.dy * (targetScale - 1);

  final scaledW = displayRect.width * targetScale;
  final scaledH = displayRect.height * targetScale;

  // Allowable translation range: image edges must not cross viewport edges.
  // After scaling around (0,0) with translation, the image left is at:
  //   displayRect.left * targetScale + tx
  // The image right is at:
  //   (displayRect.left + displayRect.width) * targetScale + tx
  final imageLeft = displayRect.left * targetScale;
  final imageTop = displayRect.top * targetScale;

  // Constraint: imageLeft + tx <= 0 (image left at or past viewport left)
  // AND imageLeft + scaledW + tx >= viewport.width (image right at or past viewport right)
  final txMin = viewport.width - imageLeft - scaledW;
  final txMax = -imageLeft;
  final tyMin = viewport.height - imageTop - scaledH;
  final tyMax = -imageTop;

  // If scaled image is smaller than viewport, clamp to center it.
  final clampedTx = scaledW < viewport.width
      ? (viewport.width - scaledW) / 2 - imageLeft
      : tx.clamp(txMin, txMax);
  final clampedTy = scaledH < viewport.height
      ? (viewport.height - scaledH) / 2 - imageTop
      : ty.clamp(tyMin, tyMax);

  return Matrix4.identity()
    ..setEntry(0, 0, targetScale)
    ..setEntry(1, 1, targetScale)
    ..setEntry(0, 3, clampedTx)
    ..setEntry(1, 3, clampedTy);
}

/// Detects whether [transform] represents a state at an image edge AND the
/// user's [velocity] is directed past that edge. Returns the edge direction
/// or null if no overscroll.
EdgeDirection? detectOverscroll({
  required Matrix4 transform,
  required Rect displayRect,
  required Size viewport,
  required Offset velocity,
}) {
  final scale = transform.entry(0, 0);
  if (scale <= _isScaledEpsilon) return null;

  final tx = transform.entry(0, 3);
  final scaledW = displayRect.width * scale;
  final imageLeftInView = displayRect.left * scale + tx;
  final imageRightInView = imageLeftInView + scaledW;

  final atLeftEdge = imageLeftInView >= -_edgeEpsilon;
  final atRightEdge = imageRightInView <= viewport.width + _edgeEpsilon;

  final vx = velocity.dx;
  if (vx.abs() <= overscrollVelocityThreshold) return null;
  // A vertical-dominant fling is a chrome swipe, not an edge overscroll.
  if (vx.abs() <= velocity.dy.abs()) return null;

  // At left edge + rightward velocity → user tried to drag image right
  //   (revealing more left of image, which doesn't exist) = retreat
  if (atLeftEdge && vx > overscrollVelocityThreshold) {
    return EdgeDirection.leftEdge;
  }
  // At right edge + leftward velocity → advance
  if (atRightEdge && vx < -overscrollVelocityThreshold) {
    return EdgeDirection.rightEdge;
  }
  return null;
}
