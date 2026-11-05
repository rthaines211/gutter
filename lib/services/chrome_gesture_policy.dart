import 'dart:ui';

import 'tap_zone_layout.dart';

/// Minimum upward/downward travel, in logical px, to count as a swipe.
const double kSwipeMinTravel = 40.0;

/// Minimum vertical velocity, in px/s, to count as a swipe even with
/// less travel. Negative going up.
const double kSwipeMinVelocity = 600.0;

/// What a reader tap should do, after chrome-visibility and reader-mode
/// rules are layered on top of the raw [TapAction] zone.
enum ChromeTapResult { left, right, back, forward, toggleChrome, hideChrome, none }

/// Resolves a normalized tap to what the reader chrome/pager should do.
///
/// Visibility and scroll-mode rules take priority over the tap-zone layout:
/// a visible chrome always hides on tap, and scroll mode always toggles.
/// Otherwise the zone's [TapAction.menu] (the layout's no-op region) toggles
/// chrome only when [offStep] (paged mode, mid-zoom/mid-spread); on-step it's
/// a no-op so the controls don't flash open while stepping through a spread.
ChromeTapResult resolveReaderTap({
  required String layout,
  required Offset normalized,
  required bool chromeVisible,
  required bool scrollMode,
  required bool offStep,
}) {
  if (chromeVisible) return ChromeTapResult.hideChrome;
  if (scrollMode) return ChromeTapResult.toggleChrome;

  switch (actionAt(layout, normalized)) {
    case TapAction.left:
      return ChromeTapResult.left;
    case TapAction.right:
      return ChromeTapResult.right;
    case TapAction.back:
      return ChromeTapResult.back;
    case TapAction.forward:
      return ChromeTapResult.forward;
    case TapAction.menu:
      return offStep ? ChromeTapResult.toggleChrome : ChromeTapResult.none;
  }
}

/// True if [delta] (pointer up minus pointer down) plus [velocityY] reads as
/// an upward swipe: vertical-dominant (|dy| > 2·|dx|), and either past [kSwipeMinTravel] px
/// of upward travel or past [kSwipeMinVelocity] px/s of upward velocity.
bool isSwipeUp(Offset delta, double velocityY) {
  if (delta.dy.abs() <= 2 * delta.dx.abs()) return false;
  return delta.dy <= -kSwipeMinTravel || velocityY <= -kSwipeMinVelocity;
}

/// Mirror of [isSwipeUp] for downward swipes.
bool isSwipeDown(Offset delta, double velocityY) {
  if (delta.dy.abs() <= 2 * delta.dx.abs()) return false;
  return delta.dy >= kSwipeMinTravel || velocityY >= kSwipeMinVelocity;
}

/// Whether a recognized swipe-up should reveal the chrome: only in paged
/// mode while on a step (not mid-zoom/mid-spread).
bool swipeShowsChrome({required bool scrollMode, required bool offStep}) {
  return !scrollMode && !offStep;
}
