import 'package:flutter/material.dart';
import '../services/zoom_math.dart';

class ZoomWrapper extends StatefulWidget {
  final Widget child;
  final TransformationController? externalController;
  final ValueChanged<bool>? onZoomChanged;
  final ValueChanged<Matrix4>? onTransformEnd;

  /// Where the image actually renders inside the viewport (BoxFit.contain rect).
  /// Required for overscroll detection.
  final Rect? displayRect;

  /// Size of the InteractiveViewer's viewport (its layout size).
  final Size? viewportSize;

  /// Fires when the user drags past an image edge with velocity above threshold.
  final ValueChanged<EdgeDirection>? onOverscroll;

  /// Extra gate on panning while scaled, read whenever the transform changes.
  /// The reader passes "off the current step, or zoom-locked" so a one-finger
  /// drag on a step stays free for the chrome swipe, while a pinch away from
  /// it (or a locked zoom) can pan.
  final bool Function()? allowPan;

  const ZoomWrapper({
    super.key,
    required this.child,
    this.externalController,
    this.onZoomChanged,
    this.onTransformEnd,
    this.displayRect,
    this.viewportSize,
    this.onOverscroll,
    this.allowPan,
  });

  @override
  State<ZoomWrapper> createState() => _ZoomWrapperState();
}

class _ZoomWrapperState extends State<ZoomWrapper> {
  TransformationController? _internalController;
  bool _lastZoomFromUser = false;

  /// Ring buffer of recent gesture deltas with timestamps for velocity estimation.
  final List<(DateTime, Offset)> _recentDeltas = [];

  TransformationController get _controller {
    if (widget.externalController != null) return widget.externalController!;
    _internalController ??= TransformationController();
    return _internalController!;
  }

  @override
  void dispose() {
    _internalController?.dispose();
    super.dispose();
  }

  bool get _isScaled => _controller.value.entry(0, 0) > 1.01;

  void _onStart(ScaleStartDetails _) {
    _recentDeltas.clear();
    final scale = _controller.value.entry(0, 0);
    if (scale > 1.01) _lastZoomFromUser = true;
  }

  void _onUpdate(ScaleUpdateDetails details) {
    _recentDeltas.add((DateTime.now(), details.focalPointDelta));
    final cutoff = DateTime.now().subtract(const Duration(milliseconds: 80));
    _recentDeltas.removeWhere((s) => s.$1.isBefore(cutoff));
  }

  void _onEnd(ScaleEndDetails _) {
    final scaleNow = _controller.value.entry(0, 0);
    if (scaleNow <= 1.01) _lastZoomFromUser = false;
    widget.onZoomChanged?.call(_isScaled);
    _checkOverscroll();
    widget.onTransformEnd?.call(_controller.value);
  }

  void _checkOverscroll() {
    final cb = widget.onOverscroll;
    final dr = widget.displayRect;
    final vp = widget.viewportSize;
    if (cb == null || dr == null || vp == null) return;
    if (_recentDeltas.isEmpty) return;

    final span = _recentDeltas.last.$1.difference(_recentDeltas.first.$1);
    if (span.inMilliseconds < 5) return;
    final dx = _recentDeltas.fold<double>(0, (s, e) => s + e.$2.dx);
    final dy = _recentDeltas.fold<double>(0, (s, e) => s + e.$2.dy);
    final seconds = span.inMicroseconds / 1e6;
    final velocity = Offset(dx / seconds, dy / seconds);

    final result = detectOverscroll(
      transform: _controller.value,
      displayRect: dr,
      viewport: vp,
      velocity: velocity,
    );
    if (result != null) cb(result);
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild on every transform change so panEnabled tracks the live
    // transform, not whatever it was when the parent last built.
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, child) => InteractiveViewer(
        transformationController: _controller,
        minScale: 1.0,
        maxScale: 5.0,
        scaleEnabled: true,
        panEnabled: _isScaled && (widget.allowPan?.call() ?? true),
        constrained: true,
        boundaryMargin: _lastZoomFromUser
            ? const EdgeInsets.all(double.infinity)
            : EdgeInsets.zero,
        onInteractionStart: _onStart,
        onInteractionUpdate: _onUpdate,
        onInteractionEnd: _onEnd,
        child: child!,
      ),
      child: widget.child,
    );
  }
}
