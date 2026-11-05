import 'dart:math';
import 'package:flutter/material.dart';

/// Computes Matrix4 transforms for navigating through a page.
///
/// [containRect] is where the image actually renders on screen (BoxFit.contain).
/// [fitMode] determines the target zoom: 'fitScreen', 'fitWidth', 'fitHeight'.
/// Transforms are relative to the contain-rendered image position.
List<Matrix4> calculatePageTransforms({
  required Rect containRect,
  required Size viewportSize,
  required bool isSpread,
  required bool isPortrait,
  required bool isRtl,
  required String fitMode,
}) {
  // Spreads always use spread navigation regardless of fit mode
  if (isSpread) {
    if (isPortrait) {
      return _spreadHalves(containRect, viewportSize, isRtl);
    }
    return _spreadGrid(containRect, viewportSize, isRtl);
  }

  // Determine target scale based on fit mode (non-spread pages only)
  final targetScale = _targetScale(containRect, viewportSize, fitMode, isPortrait, isSpread);

  if (targetScale <= 1.001) {
    return [Matrix4.identity()];
  }

  // Apply target zoom and chunk if needed
  final scaledWidth = containRect.width * targetScale;
  final scaledHeight = containRect.height * targetScale;
  final tx = -containRect.left * targetScale;

  // Check vertical overflow
  if (scaledHeight > viewportSize.height * 1.05) {
    return _verticalChunks(
      targetScale,
      tx,
      containRect.top * targetScale,
      scaledHeight,
      viewportSize.height,
    );
  }

  // Check horizontal overflow
  if (scaledWidth > viewportSize.width * 1.05) {
    return _horizontalChunks(
      targetScale,
      containRect.left * targetScale,
      -containRect.top * targetScale + (viewportSize.height - scaledHeight) / 2,
      scaledWidth,
      viewportSize.width,
    );
  }

  // Single transform: zoom and center
  final ty = (viewportSize.height - scaledHeight) / 2;
  return [_makeTransform(targetScale, tx, ty)];
}

/// Determine the target scale based on fit mode.
double _targetScale(Rect containRect, Size viewportSize, String fitMode, bool isPortrait, bool isSpread) {
  switch (fitMode) {
    case 'fitWidth':
      // User wants page width to fill screen width
      // "fitWidth" after the swap = BoxFit.fitHeight in _boxFitForSetting
      // We need to zoom so the page fills the viewport width
      final scale = viewportSize.width / containRect.width;
      return scale;

    case 'fitHeight':
      // User wants page height to fill screen height
      final scale = viewportSize.height / containRect.height;
      return scale;

    case 'fitScreen':
    default:
      // For fitScreen in landscape with narrow pages, auto-zoom to width
      if (!isPortrait && !isSpread && containRect.width < viewportSize.width * 0.95) {
        return viewportSize.width / containRect.width;
      }
      return 1.0;
  }
}

/// Portrait spread: full view → zoom left half → zoom right half.
/// Zooms each half to fit entirely within viewport (no clipping).
List<Matrix4> _spreadHalves(Rect containRect, Size viewportSize, bool isRtl) {
  final halfWidth = containRect.width / 2;
  final widthZoom = viewportSize.width / halfWidth;
  final heightZoom = viewportSize.height / containRect.height;
  final zoom = min(widthZoom, heightZoom);

  if (zoom <= 1.01) return [Matrix4.identity()];

  final scaledHeight = containRect.height * zoom;
  final ty = (viewportSize.height - scaledHeight) / 2 - containRect.top * zoom;

  final leftTx = -containRect.left * zoom;
  final rightTx = -(containRect.left + halfWidth) * zoom;

  final leftTransform = _makeTransform(zoom, leftTx, ty);
  final rightTransform = _makeTransform(zoom, rightTx, ty);

  if (isRtl) {
    return [Matrix4.identity(), rightTransform, leftTransform];
  }
  return [Matrix4.identity(), leftTransform, rightTransform];
}

/// Landscape spread grid: full view first, then cols×rows grid at half-width zoom.
/// Matches LCS behavior — zoom so half the spread fills viewport width,
/// then divide into viewport-sized cells in reading order.
List<Matrix4> _spreadGrid(Rect containRect, Size viewportSize, bool isRtl) {
  final halfWidth = containRect.width / 2;
  final zoom = viewportSize.width / halfWidth;

  // If zoom is negligible, just show full view
  if (zoom <= 1.01) return [Matrix4.identity()];

  final zoomedWidth = containRect.width * zoom;
  final zoomedHeight = containRect.height * zoom;
  final totalScrollX = zoomedWidth - viewportSize.width;
  final totalScrollY = zoomedHeight - viewportSize.height;

  final cols = totalScrollX <= 0 ? 1 : (totalScrollX / viewportSize.width).ceil() + 1;
  final rows = totalScrollY <= 0 ? 1 : (totalScrollY / viewportSize.height).ceil() + 1;
  final stepX = cols > 1 ? totalScrollX / (cols - 1) : 0.0;
  final stepY = rows > 1 ? totalScrollY / (rows - 1) : 0.0;

  final contentLeft = containRect.left * zoom;
  final contentTop = containRect.top * zoom;

  final positions = <Matrix4>[Matrix4.identity()]; // full view first
  for (var row = 0; row < rows; row++) {
    final rowPositions = <Matrix4>[];
    for (var col = 0; col < cols; col++) {
      final tx = -(contentLeft + col * stepX);
      final ty = -(contentTop + row * stepY);
      rowPositions.add(_makeTransform(zoom, tx, ty));
    }
    if (isRtl) {
      positions.addAll(rowPositions.reversed);
    } else {
      positions.addAll(rowPositions);
    }
  }

  return positions;
}

/// Generate vertical chunk transforms.
List<Matrix4> _verticalChunks(
  double scale,
  double tx,
  double scaledTop,
  double scaledHeight,
  double viewportHeight,
) {
  final overflow = scaledHeight - viewportHeight;
  if (overflow <= 0) {
    final ty = (viewportHeight - scaledHeight) / 2;
    return [_makeTransform(scale, tx, ty)];
  }

  final stepSize = viewportHeight * 0.8;
  final numSteps = max(2, (overflow / stepSize).ceil() + 1);
  final stepOffset = overflow / (numSteps - 1);

  final transforms = <Matrix4>[];
  for (var i = 0; i < numSteps; i++) {
    final ty = -scaledTop - (i * stepOffset);
    transforms.add(_makeTransform(scale, tx, ty));
  }
  return transforms;
}

/// Generate horizontal chunk transforms.
List<Matrix4> _horizontalChunks(
  double scale,
  double scaledLeft,
  double ty,
  double scaledWidth,
  double viewportWidth,
) {
  final overflow = scaledWidth - viewportWidth;
  if (overflow <= 0) {
    final txCenter = (viewportWidth - scaledWidth) / 2;
    return [_makeTransform(scale, txCenter, ty)];
  }

  final stepSize = viewportWidth * 0.8;
  final numSteps = max(2, (overflow / stepSize).ceil() + 1);
  final stepOffset = overflow / (numSteps - 1);

  final transforms = <Matrix4>[];
  for (var i = 0; i < numSteps; i++) {
    final txStep = -scaledLeft - (i * stepOffset);
    transforms.add(_makeTransform(scale, txStep, ty));
  }
  return transforms;
}

/// Build a Matrix4 with uniform scale and translation.
Matrix4 _makeTransform(double scale, double tx, double ty) {
  return Matrix4.identity()
    ..setEntry(0, 0, scale)
    ..setEntry(1, 1, scale)
    ..setEntry(0, 3, tx)
    ..setEntry(1, 3, ty);
}
