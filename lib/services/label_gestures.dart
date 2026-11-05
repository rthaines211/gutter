import 'package:flutter/painting.dart';

enum TwoFingerGesture { undo, prevPage, nextPage, pinch, none }

TwoFingerGesture classifyTwoFinger({
  required Duration held,
  required Offset centroidDelta,
  required double scaleChange,
}) {
  // Rule 1: scaleChange > 0.08 → pinch
  if (scaleChange > 0.08) {
    return TwoFingerGesture.pinch;
  }

  // Rule 2: |dx| >= 80 && |dx| > 2*|dy| → nextPage if dx < 0 else prevPage
  final dx = centroidDelta.dx;
  final dy = centroidDelta.dy;
  final absDx = dx.abs();
  final absDy = dy.abs();

  if (absDx >= 80 && absDx > 2 * absDy) {
    return dx < 0 ? TwoFingerGesture.nextPage : TwoFingerGesture.prevPage;
  }

  // Rule 3: held <= 250ms && centroid moved < 12 → undo
  final centroidDistance =
      centroidDelta.distance;
  if (held.inMilliseconds <= 250 && centroidDistance < 12) {
    return TwoFingerGesture.undo;
  }

  // Default: none
  return TwoFingerGesture.none;
}

enum TapAction { select, deselect, toggleKind, delete }

class TapResolver {
  TapAction? onTap({
    required int? hitBox,
    required int selected,
    required Duration sinceLastTap,
    required int? lastTapBox,
    required bool balloons,
  }) {
    // Rule 1: same box tapped again within 300 ms → delete
    if (hitBox != null &&
        hitBox == lastTapBox &&
        sinceLastTap.inMilliseconds <= 300) {
      return TapAction.delete;
    }

    // Rule 2: tap on empty (hitBox is null) → deselect
    if (hitBox == null) {
      return TapAction.deselect;
    }

    // Rule 3: tap on unselected box → select
    if (hitBox != selected) {
      return TapAction.select;
    }

    // Rule 4: tap on selected box (not a double) → toggleKind if balloons else null
    return balloons ? TapAction.toggleKind : null;
  }
}

enum OneFingerIntent { pan, resize, move, draw }

OneFingerIntent intentFor({
  required bool zoomed,
  required int? hitBox,
  required bool onEdge,
  required int selected,
}) {
  // Rule 1: selected box edge → resize
  if (hitBox == selected && onEdge) {
    return OneFingerIntent.resize;
  }

  // Rule 2: inside selected box → move
  if (hitBox == selected && !onEdge) {
    return OneFingerIntent.move;
  }

  // Rule 3: pan when zoomed and not on any box, else draw
  if (zoomed && hitBox == null) {
    return OneFingerIntent.pan;
  }

  // Otherwise: draw
  return OneFingerIntent.draw;
}
