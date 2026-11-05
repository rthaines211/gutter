import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../services/chrome_gesture_policy.dart';

/// Overlay that resolves taps via a named [layout] (see
/// `services/tap_zone_layout.dart`) plus the chrome rules in
/// `services/chrome_gesture_policy.dart`, double-taps to zoom, and vertical
/// swipes to show/hide the reader chrome.
///
/// Uses raw [Listener] instead of [GestureDetector] to bypass the gesture
/// arena — this prevents InteractiveViewer from stealing tap events. Single
/// taps fire after a 250ms double-tap window to allow disambiguation.
///
/// Reader state is passed as getters so it's read at gesture time.
class TapZoneOverlay extends StatefulWidget {
  final String layout;
  final VoidCallback? onLeft;
  final VoidCallback? onRight;
  final VoidCallback? onBack;
  final VoidCallback? onForward;
  final bool Function() chromeVisible;
  final bool Function() scrollMode;
  final bool Function() offStep;
  final VoidCallback onShowChrome;
  final VoidCallback onHideChrome;
  final void Function(Offset positionInOverlay)? onDoubleTap;
  final void Function(Offset positionInOverlay)? onLongPress;
  final VoidCallback? onTwoFingerTap;

  const TapZoneOverlay({
    super.key,
    required this.layout,
    this.onLeft,
    this.onRight,
    this.onBack,
    this.onForward,
    required this.chromeVisible,
    required this.scrollMode,
    required this.offStep,
    required this.onShowChrome,
    required this.onHideChrome,
    this.onDoubleTap,
    this.onLongPress,
    this.onTwoFingerTap,
  });

  @override
  State<TapZoneOverlay> createState() => _TapZoneOverlayState();
}

class _TapZoneOverlayState extends State<TapZoneOverlay> {
  void _dispatch(Offset local, Size size) {
    final norm = Offset(
      size.width == 0 ? 0 : local.dx / size.width,
      size.height == 0 ? 0 : local.dy / size.height,
    );
    final visible = widget.chromeVisible();
    switch (resolveReaderTap(
      layout: widget.layout,
      normalized: norm,
      chromeVisible: visible,
      scrollMode: widget.scrollMode(),
      offStep: widget.offStep(),
    )) {
      case ChromeTapResult.left:
        widget.onLeft?.call();
      case ChromeTapResult.right:
        widget.onRight?.call();
      case ChromeTapResult.back:
        widget.onBack?.call();
      case ChromeTapResult.forward:
        widget.onForward?.call();
      case ChromeTapResult.toggleChrome:
        visible ? widget.onHideChrome() : widget.onShowChrome();
      case ChromeTapResult.hideChrome:
        widget.onHideChrome();
      case ChromeTapResult.none:
        break;
    }
  }

  void _swipe(Offset delta, double velocityY) {
    if (isSwipeUp(delta, velocityY)) {
      if (swipeShowsChrome(scrollMode: widget.scrollMode(), offStep: widget.offStep())) {
        widget.onShowChrome();
      }
    } else if (isSwipeDown(delta, velocityY) && widget.chromeVisible()) {
      widget.onHideChrome();
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return _TapZone(
          onTap: (pos) => _dispatch(pos, size),
          onSwipe: _swipe,
          onDoubleTap: widget.onDoubleTap,
          onLongPress: widget.onLongPress,
          onTwoFingerTap: widget.onTwoFingerTap,
        );
      },
    );
  }
}

class _TapZone extends StatefulWidget {
  final void Function(Offset positionInZone)? onTap;
  final void Function(Offset positionInZone)? onDoubleTap;
  final void Function(Offset positionInZone)? onLongPress;
  final void Function(Offset delta, double velocityY)? onSwipe;
  final VoidCallback? onTwoFingerTap;
  const _TapZone({this.onTap, this.onSwipe, this.onDoubleTap, this.onLongPress, this.onTwoFingerTap});

  @override
  State<_TapZone> createState() => _TapZoneState();
}

class _TapZoneState extends State<_TapZone> {
  Offset? _downPos;
  DateTime? _downTime;
  Timer? _pendingTapTimer;
  Offset? _firstTapPos;
  VelocityTracker? _velocity;
  // One-finger gestures only: track the first pointer; any second pointer
  // (e.g. a pinch) voids the gesture so it yields no tap and no swipe.
  int? _pointer;
  bool _multiTouch = false;

  static const _maxDistance = 20.0;
  static const _maxDuration = Duration(milliseconds: 300);
  static const _doubleTapWindow = Duration(milliseconds: 250);
  static const _doubleTapMaxMove = 50.0;

  Timer? _longPressTimer;
  bool _longPressed = false;
  static const _longPressDelay = Duration(milliseconds: 500);

  // Two-finger tap: exactly two pointers, both down and up within
  // _twoFingerMaxDuration, neither moving past _maxDistance (so a pinch,
  // which moves, never counts). Tracked apart from the one-finger state.
  final Map<int, Offset> _touchDowns = {};
  int _touchesSeen = 0;
  bool _touchMoved = false;
  DateTime? _touchStart;
  static const _twoFingerMaxDuration = Duration(milliseconds: 400);

  void _touchDown(PointerDownEvent e) {
    if (_touchDowns.isEmpty) {
      _touchesSeen = 0;
      _touchMoved = false;
      _touchStart = DateTime.now();
    }
    _touchDowns[e.pointer] = e.localPosition;
    _touchesSeen++;
  }

  void _touchMove(PointerMoveEvent e) {
    final down = _touchDowns[e.pointer];
    if (down != null && (e.localPosition - down).distance >= _maxDistance) _touchMoved = true;
  }

  void _touchUp(PointerEvent e, {bool cancelled = false}) {
    if (_touchDowns.remove(e.pointer) == null) return;
    if (cancelled) _touchMoved = true;
    if (_touchDowns.isEmpty &&
        _touchesSeen == 2 &&
        !_touchMoved &&
        DateTime.now().difference(_touchStart!) < _twoFingerMaxDuration) {
      widget.onTwoFingerTap?.call();
    }
  }

  @override
  void dispose() {
    _pendingTapTimer?.cancel();
    _longPressTimer?.cancel();
    super.dispose();
  }

  void _onTapQualified(Offset position) {
    final firstPos = _firstTapPos;
    if (_pendingTapTimer != null && firstPos != null) {
      if ((position - firstPos).distance < _doubleTapMaxMove) {
        _pendingTapTimer!.cancel();
        _pendingTapTimer = null;
        _firstTapPos = null;
        if (widget.onDoubleTap != null) {
          widget.onDoubleTap!(position);
        } else {
          widget.onTap?.call(position);
        }
        return;
      }
      _pendingTapTimer!.cancel();
      _pendingTapTimer = null;
      _firstTapPos = null;
      widget.onTap?.call(firstPos);
    }
    if (widget.onDoubleTap == null) {
      widget.onTap?.call(position);
      return;
    }
    _firstTapPos = position;
    _pendingTapTimer = Timer(_doubleTapWindow, () {
      _pendingTapTimer = null;
      _firstTapPos = null;
      widget.onTap?.call(position);
    });
  }

  void _reset() {
    _pointer = null;
    _downPos = null;
    _downTime = null;
    _velocity = null;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (e) {
        _touchDown(e);
        if (_pointer != null) {
          _multiTouch = true;
          _longPressTimer?.cancel();
          return;
        }
        _pointer = e.pointer;
        _multiTouch = false;
        _downPos = e.localPosition;
        _downTime = DateTime.now();
        _velocity = VelocityTracker.withKind(e.kind)
          ..addPosition(e.timeStamp, e.localPosition);
        _longPressed = false;
        _longPressTimer?.cancel();
        final onLongPress = widget.onLongPress;
        if (onLongPress != null) {
          final pos = e.localPosition;
          _longPressTimer = Timer(_longPressDelay, () {
            _longPressed = true;
            onLongPress(pos);
          });
        }
      },
      onPointerMove: (e) {
        _touchMove(e);
        if (e.pointer != _pointer) return;
        _velocity?.addPosition(e.timeStamp, e.localPosition);
        final down = _downPos;
        if (down != null && (e.localPosition - down).distance >= _maxDistance) {
          _longPressTimer?.cancel();
        }
      },
      onPointerUp: (e) {
        _touchUp(e);
        if (e.pointer != _pointer) return;
        _longPressTimer?.cancel();
        if (!_multiTouch && !_longPressed && _downPos != null && _downTime != null) {
          final moved = (e.localPosition - _downPos!).distance;
          final elapsed = DateTime.now().difference(_downTime!);
          if (moved >= _maxDistance) {
            // Past the tap slop: a swipe candidate, never a tap.
            final vy = _velocity?.getVelocity().pixelsPerSecond.dy ?? 0;
            widget.onSwipe?.call(e.localPosition - _downPos!, vy);
          } else if (elapsed < _maxDuration) {
            _onTapQualified(e.localPosition);
          }
        }
        _reset();
      },
      onPointerCancel: (e) {
        _touchUp(e, cancelled: true);
        if (e.pointer != _pointer) return;
        _longPressTimer?.cancel();
        _reset();
      },
      child: const SizedBox.expand(),
    );
  }
}
