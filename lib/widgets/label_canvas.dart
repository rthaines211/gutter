// lib/widgets/label_canvas.dart
//
// The labeller's page: image + boxes painted over its contain rect, with
// finger gestures (see the design doc's finger mapping). Pointer handling is
// a raw Listener so one/two-finger rules come from label_gestures.dart, not
// from the gesture arena.
import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../services/display_rect_calculator.dart';
import '../services/label_client.dart';
import '../services/label_editor.dart';
import '../services/label_gestures.dart';

const _selColor = Color(0xFFFF9F1A);
const _slop = 10.0; // px before a touch counts as a drag (web tool's slop)
const _grab = 22.0; // px edge grab radius for resizing the selected box

Color labelBoxColor(int k) =>
    HSLColor.fromAHSL(1, (k * 137.5) % 360, .85, .6).toColor();

class LabelCanvas extends StatefulWidget {
  final LabelEditor editor;
  final LabelPage page;
  final String imageUrl;
  final LabelMode mode;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  const LabelCanvas({
    super.key,
    required this.editor,
    required this.page,
    required this.imageUrl,
    required this.mode,
    required this.onPrev,
    required this.onNext,
  });

  @override
  State<LabelCanvas> createState() => _LabelCanvasState();
}

class _LabelCanvasState extends State<LabelCanvas> {
  Matrix4 _xf = Matrix4.identity();
  Rect _rect = Rect.zero; // contain rect, in untransformed canvas coords
  final Map<int, Offset> _pointers = {};

  // Two-finger state (lasts until every finger is up).
  bool _two = false;
  bool _pinching = false;
  Duration _twoStart = Duration.zero;
  Offset _c0 = Offset.zero, _cLast = Offset.zero;
  double _d0 = 1, _dLast = 1;
  Matrix4 _xf0 = Matrix4.identity();

  // One-finger state.
  Offset? _down; // screen pos
  bool _dragging = false;
  OneFingerIntent _intent = OneFingerIntent.draw;
  int? _hit;
  ({bool l, bool r, bool t, bool b})? _edges;
  Box? _orig;
  Offset _downFrac = Offset.zero;
  Rect? _drawRect; // fractions, while drawing

  // Taps.
  final _taps = TapResolver();
  Duration? _lastTapAt;
  int? _lastTapBox;
  Timer? _toggleTimer;
  int? _toggleBox;

  LabelEditor get _e => widget.editor;
  double get _scale => _xf.getMaxScaleOnAxis();

  @override
  void didUpdateWidget(LabelCanvas old) {
    super.didUpdateWidget(old);
    if (old.editor != widget.editor) {
      _xf = Matrix4.identity();
      _cancelToggle();
      _lastTapBox = null;
    }
  }

  @override
  void dispose() {
    _cancelToggle();
    super.dispose();
  }

  void _cancelToggle() {
    _toggleTimer?.cancel();
    _toggleTimer = null;
    _toggleBox = null;
  }

  /// Screen position -> page fractions, clamped to [0, 1].
  Offset _frac(Offset p) {
    final q = MatrixUtils.transformPoint(Matrix4.inverted(_xf), p);
    return Offset(
      ((q.dx - _rect.left) / _rect.width).clamp(0.0, 1.0),
      ((q.dy - _rect.top) / _rect.height).clamp(0.0, 1.0),
    );
  }

  Offset get _centroid {
    final ps = _pointers.values.take(2).toList();
    return (ps[0] + ps[1]) / 2;
  }

  double get _spread {
    final ps = _pointers.values.take(2).toList();
    return math.max((ps[0] - ps[1]).distance, 1);
  }

  void _onDown(PointerDownEvent ev) {
    _pointers[ev.pointer] = ev.localPosition;
    if (_rect.isEmpty) return;
    if (_pointers.length == 1 && !_two) {
      _startOne(ev.localPosition);
    } else if (_pointers.length == 2 && !_two) {
      _abortOne();
      _two = true;
      _pinching = false;
      _twoStart = ev.timeStamp;
      _c0 = _cLast = _centroid;
      _d0 = _dLast = _spread;
      _xf0 = _xf.clone();
    }
  }

  void _startOne(Offset p) {
    _down = p;
    _dragging = false;
    _drawRect = null;
    _downFrac = _frac(p);
    final gx = _grab / (_rect.width * _scale);
    final gy = _grab / (_rect.height * _scale);
    final order = _e.step == LabelStep.order;
    _hit = LabelEditor.hitTest(
      _e.boxes,
      _downFrac.dx,
      _downFrac.dy,
      selected: _e.selected,
      grabX: gx,
      grabY: gy,
      skip: order ? (k) => _e.order.contains(k) : null,
    );
    final ed = _hit == null
        ? null
        : LabelEditor.edgesAt(_e.boxes, _downFrac.dx, _downFrac.dy,
            selected: _e.selected, grabX: gx, grabY: gy);
    _edges = ed;
    _orig = _hit == null ? null : List<double>.from(_e.boxes[_hit!]);
    _intent = intentFor(
      zoomed: _scale > 1.01,
      hitBox: _hit,
      onEdge: ed != null && (ed.l || ed.r || ed.t || ed.b),
      selected: _e.selected,
    );
  }

  /// A second finger landed: drop whatever the first finger was doing.
  void _abortOne() {
    if (_dragging &&
        _orig != null &&
        (_intent == OneFingerIntent.move ||
            _intent == OneFingerIntent.resize)) {
      _e.moveBoxTo(_hit!, _orig!);
    }
    _down = null;
    _dragging = false;
    setState(() => _drawRect = null);
  }

  void _onMove(PointerMoveEvent ev) {
    if (!_pointers.containsKey(ev.pointer)) return;
    _pointers[ev.pointer] = ev.localPosition;
    if (_two) {
      if (_pointers.length < 2) return;
      _cLast = _centroid;
      _dLast = _spread;
      if (!_pinching && (_dLast / _d0 - 1).abs() > 0.08) _pinching = true;
      if (_pinching) _zoom();
      return;
    }
    final down = _down;
    if (down == null) return;
    if (!_dragging) {
      if ((ev.localPosition - down).distance < _slop) return;
      _dragging = true;
      _cancelToggle();
    }
    // Order step: taps only (plus panning while zoomed).
    if (_e.step == LabelStep.order && _intent != OneFingerIntent.pan) return;
    final f = _frac(ev.localPosition);
    switch (_intent) {
      case OneFingerIntent.pan:
        _pan(ev.localDelta);
      case OneFingerIntent.resize:
        _e.moveBoxTo(_hit!, LabelEditor.resized(_orig!, _edges!, f.dx, f.dy));
      case OneFingerIntent.move:
        _e.moveBoxTo(
          _hit!,
          LabelEditor.moved(_orig!, f.dx - _downFrac.dx, f.dy - _downFrac.dy),
        );
      case OneFingerIntent.draw:
        setState(() => _drawRect = Rect.fromPoints(_downFrac, f));
    }
  }

  void _onUp(PointerEvent ev) {
    _pointers.remove(ev.pointer);
    if (_two) {
      if (_pointers.isNotEmpty) return;
      _two = false;
      if (!_pinching) {
        final g = classifyTwoFinger(
          held: ev.timeStamp - _twoStart,
          centroidDelta: _cLast - _c0,
          scaleChange: (_dLast / _d0 - 1).abs(),
        );
        switch (g) {
          case TwoFingerGesture.undo:
            _cancelToggle();
            _e.undo();
          case TwoFingerGesture.prevPage:
            widget.onPrev();
          case TwoFingerGesture.nextPage:
            widget.onNext();
          case TwoFingerGesture.pinch:
          case TwoFingerGesture.none:
            break;
        }
      }
      return;
    }
    if (_down == null) return;
    _down = null;
    if (ev is PointerCancelEvent) {
      _abortOne();
      return;
    }
    if (!_dragging) {
      _tap(ev.timeStamp);
      return;
    }
    _dragging = false;
    if (_e.step == LabelStep.order) return;
    switch (_intent) {
      case OneFingerIntent.draw:
        final r = _drawRect;
        setState(() => _drawRect = null);
        if (r != null) _e.addBox([r.left, r.top, r.right, r.bottom]);
      case OneFingerIntent.move:
      case OneFingerIntent.resize:
        _e.commitDrag(_hit!, _orig!);
      case OneFingerIntent.pan:
        break;
    }
  }

  void _tap(Duration at) {
    if (_e.step == LabelStep.order) {
      if (_hit != null) _e.tapOrder(_hit!);
      return;
    }
    final action = _taps.onTap(
      hitBox: _hit,
      selected: _e.selected,
      sinceLastTap: _lastTapAt == null ? const Duration(days: 1) : at - _lastTapAt!,
      lastTapBox: _lastTapBox,
      balloons: widget.mode == LabelMode.balloons,
    );
    _lastTapAt = at;
    _lastTapBox = _hit;
    switch (action) {
      case TapAction.select:
        _e.select(_hit!);
      case TapAction.deselect:
        _e.deselect();
      case TapAction.delete:
        if (_toggleBox == _hit) _cancelToggle();
        _e.select(_hit!);
        _e.deleteSelected();
        _lastTapBox = null;
      case TapAction.toggleKind:
        // Wait out a possible second tap (that would be a delete).
        _cancelToggle();
        _toggleBox = _hit;
        final box = _hit;
        _toggleTimer = Timer(const Duration(milliseconds: 300), () {
          _toggleTimer = null;
          _toggleBox = null;
          if (_e.selected == box) _e.toggleKind();
        });
      case null:
        break;
    }
  }

  void _zoom() {
    final s0 = _xf0.getMaxScaleOnAxis();
    final s = (s0 * _dLast / _d0).clamp(1.0, 4.0);
    final p = MatrixUtils.transformPoint(Matrix4.inverted(_xf0), _c0);
    final m = Matrix4.identity()
      ..translateByDouble(_cLast.dx, _cLast.dy, 0, 1)
      ..scaleByDouble(s, s, 1, 1)
      ..translateByDouble(-p.dx, -p.dy, 0, 1);
    setState(() => _xf = _clamped(m));
  }

  void _pan(Offset d) {
    final m = Matrix4.translationValues(d.dx, d.dy, 0)..multiply(_xf);
    setState(() => _xf = _clamped(m));
  }

  /// Keep the zoomed content covering the canvas (no dragging into black).
  Matrix4 _clamped(Matrix4 m) {
    final size = context.size ?? Size.zero;
    final s = m.getMaxScaleOnAxis();
    final t = m.getTranslation();
    final tx = t.x.clamp(size.width * (1 - s), 0.0);
    final ty = t.y.clamp(size.height * (1 - s), 0.0);
    return m..setTranslationRaw(tx, ty, 0);
  }

  @override
  Widget build(BuildContext context) {
    final page = widget.page;
    return LayoutBuilder(
      builder: (context, c) {
        _rect = page.w <= 0 || page.h <= 0
            ? Rect.zero
            : calculateDisplayRect(
                imageWidth: page.w,
                imageHeight: page.h,
                viewportWidth: c.maxWidth,
                viewportHeight: c.maxHeight,
                fit: BoxFit.contain,
              );
        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _onDown,
          onPointerMove: _onMove,
          onPointerUp: _onUp,
          onPointerCancel: _onUp,
          child: ClipRect(
            child: Transform(
              transform: _xf,
              child: Stack(
                children: [
                  Positioned.fromRect(
                    rect: _rect,
                    child: Image(
                      image: CachedNetworkImageProvider(widget.imageUrl),
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                      errorBuilder: (_, _, _) =>
                          const ColoredBox(color: Color(0xFF222222)),
                    ),
                  ),
                  Positioned.fromRect(
                    rect: _rect,
                    child: ListenableBuilder(
                      listenable: widget.editor,
                      builder: (_, _) => CustomPaint(
                        size: _rect.size,
                        painter: _BoxPainter(
                          editor: widget.editor,
                          context: widget.mode == LabelMode.balloons
                              ? page.context
                              : const [],
                          drawing: _drawRect,
                          scale: _scale,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _BoxPainter extends CustomPainter {
  final LabelEditor editor;
  final List<Box> context;
  final Rect? drawing;
  final double scale;

  _BoxPainter({
    required this.editor,
    required this.context,
    required this.drawing,
    required this.scale,
  });

  Rect _r(Box b, Size s) =>
      Rect.fromLTRB(b[0] * s.width, b[1] * s.height, b[2] * s.width, b[3] * s.height);

  @override
  void paint(Canvas canvas, Size size) {
    final px = 1 / scale; // keep strokes ~constant on screen while zoomed
    final ctx = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = px
      ..color = const Color(0x88888888);
    for (final b in context) {
      _dashRect(canvas, _r(b, size), ctx, 5 * px, 4 * px);
    }

    final ordering = editor.step == LabelStep.order;
    for (var k = 0; k < editor.boxes.length; k++) {
      final r = _r(editor.boxes[k], size);
      final col = labelBoxColor(k);
      final caption = editor.kinds.length > k && editor.kinds[k] == 'caption' &&
          editor.mode == LabelMode.balloons;
      canvas.drawRect(r, Paint()..color = col.withValues(alpha: .12));
      if (k == editor.selected) {
        final p = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2 * px
          ..color = _selColor;
        _dashRect(canvas, r, p, 6 * px, 4 * px);
        final h = Paint()..color = _selColor;
        for (final c in [r.topLeft, r.topRight, r.bottomLeft, r.bottomRight]) {
          canvas.drawCircle(c, 7 * px, h);
        }
      } else {
        final p = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = (caption ? 3 : 2) * px
          ..color = col;
        if (caption) {
          _dashRect(canvas, r, p, 2 * px, 3 * px);
        } else {
          canvas.drawRect(r, p);
        }
      }
      if (caption) {
        _label(canvas, 'caption', r.topRight, col, 9 * px);
      }
      if (ordering) {
        final n = editor.order.indexOf(k);
        final rad = 13 * px;
        if (n >= 0) {
          canvas.drawCircle(r.center, rad, Paint()..color = col);
          _text(canvas, '${n + 1}', r.center, Colors.black, 13 * px);
        } else {
          canvas.drawCircle(r.center, rad, Paint()..color = const Color(0x88000000));
          _dashCircle(canvas, r.center, rad, px);
          _text(canvas, '?', r.center, Colors.white, 13 * px);
        }
      } else if (editor.orderFresh && editor.order.contains(k)) {
        // Boxes step: the server's reading order, so boxes are easy to tell apart.
        final n = editor.order.indexOf(k);
        canvas.drawCircle(r.center, 13 * px, Paint()..color = col);
        _text(canvas, '${n + 1}', r.center, Colors.black, 13 * px);
      }
    }

    final d = drawing;
    if (d != null) {
      canvas.drawRect(
        Rect.fromLTRB(d.left * size.width, d.top * size.height,
            d.right * size.width, d.bottom * size.height),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2 * px
          ..color = _selColor,
      );
    }
  }

  void _text(Canvas c, String s, Offset center, Color color, double size) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(color: color, fontSize: size, fontWeight: FontWeight.w700),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, center - Offset(tp.width / 2, tp.height / 2));
  }

  void _label(Canvas c, String s, Offset topRight, Color bg, double size) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(color: Colors.black, fontSize: size)),
      textDirection: TextDirection.ltr,
    )..layout();
    final r = Rect.fromLTWH(
        topRight.dx - tp.width - size * .6, topRight.dy, tp.width + size * .6, tp.height);
    c.drawRect(r, Paint()..color = bg);
    tp.paint(c, r.topLeft + Offset(size * .3, 0));
  }

  void _dashCircle(Canvas c, Offset center, double r, double px) {
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = px
      ..color = Colors.white;
    const n = 12;
    for (var i = 0; i < n; i++) {
      c.drawArc(Rect.fromCircle(center: center, radius: r),
          i * 2 * math.pi / n, math.pi / n, false, p);
    }
  }

  void _dashRect(Canvas c, Rect r, Paint p, double dash, double gap) {
    void line(Offset a, Offset b) {
      final len = (b - a).distance;
      if (len == 0) return;
      final dir = (b - a) / len;
      for (var t = 0.0; t < len; t += dash + gap) {
        c.drawLine(a + dir * t, a + dir * math.min(t + dash, len), p);
      }
    }

    line(r.topLeft, r.topRight);
    line(r.topRight, r.bottomRight);
    line(r.bottomRight, r.bottomLeft);
    line(r.bottomLeft, r.topLeft);
  }

  @override
  bool shouldRepaint(_BoxPainter old) => true;
}
