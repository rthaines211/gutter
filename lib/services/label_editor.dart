// lib/services/label_editor.dart
//
// Pure editor state for the iPad labeller. Ports the semantics of the web
// labeller's JS (~/projects/panel-labels/index.html lines 60-190): box/kind
// state with undo, stale-order detection (orderFor/fresh), and the
// hit-test + clamp math used for drag gestures. No widgets, no HTTP.
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

enum LabelMode {
  panels,
  balloons;

  String get queuePath =>
      this == LabelMode.panels ? 'pages.json' : 'balloon_pages.json';
  String get donePath =>
      this == LabelMode.panels ? 'done.json' : 'balloons-done.json';
  String get dir => this == LabelMode.panels ? 'labels' : 'balloons';
  String get prefillDir => this == LabelMode.panels ? 'prefill' : 'bprefill';
  String get noneLabel =>
      this == LabelMode.panels ? 'No panels' : 'No balloons';
  String get apiName => this == LabelMode.panels ? 'panels' : 'balloons';
}

enum LabelStep { boxes, order }

/// `[x0, y0, x1, y1]` as fractions of the page image.
typedef Box = List<double>;

/// One undo-stack entry. Mirrors the object literals pushed onto `hist` in
/// index.html; the shape of the non-null fields says which action it is,
/// in the same precedence `undo()` there checks them.
class _HistEntry {
  final List<Box>? all;
  final List<String>? kinds;
  final int? k;
  final bool add;
  final bool del;
  final Box? box;
  final String? kind;

  const _HistEntry({
    this.all,
    this.kinds,
    this.k,
    this.add = false,
    this.del = false,
    this.box,
    this.kind,
  });
}

Box _copyBox(Box b) => List<double>.from(b);
List<Box> _copyBoxes(List<Box> bs) => bs.map(_copyBox).toList();

class LabelEditor extends ChangeNotifier {
  final LabelMode mode;
  final List<Box> _prefillBoxes;
  final List<String> _prefillKinds;

  List<Box> _boxes;
  List<String> _kinds;
  List<int> _order = [];
  String? _orderFor;
  LabelStep _step = LabelStep.boxes;
  int _selected = -1;
  String _note;
  final List<_HistEntry> _hist = [];

  LabelEditor({
    required this.mode,
    required List<Box> prefillBoxes,
    required List<String> prefillKinds,
    ({List<Box> boxes, List<String> kinds, List<int> order, String note})?
        saved,
  })  : _prefillBoxes = _copyBoxes(prefillBoxes),
        _prefillKinds = _alignKinds(prefillKinds, prefillBoxes.length),
        _boxes = _copyBoxes(saved?.boxes ?? prefillBoxes),
        _kinds = _alignKinds(
          saved?.kinds ?? prefillKinds,
          (saved?.boxes ?? prefillBoxes).length,
        ),
        _note = saved?.note ?? '' {
    if (saved != null) {
      final ok = saved.order.length == _boxes.length;
      _order = ok ? List<int>.from(saved.order) : [];
      _orderFor = ok ? boxesKey : null;
    }
  }

  /// Pads or truncates [kinds] to [length] with 'balloon', the way JS's
  /// `v.kinds||boxes.map(()=>'balloon')` and prefill `x.kind||'balloon'`
  /// default a missing kind. A panels saved label has no kinds at all, so
  /// callers may legitimately pass an empty list.
  static List<String> _alignKinds(List<String> kinds, int length) {
    if (kinds.length == length) return List<String>.from(kinds);
    return List<String>.generate(
      length,
      (i) => i < kinds.length ? kinds[i] : 'balloon',
    );
  }

  // --- state getters ---

  List<Box> get boxes => _boxes;
  List<String> get kinds => _kinds;
  List<int> get order => _order;
  LabelStep get step => _step;
  int get selected => _selected;
  String get note => _note;
  set note(String value) {
    _note = value;
    notifyListeners();
  }

  bool get canUndo => _hist.isNotEmpty;

  /// JSON of the current boxes; the `orderFor` analogue from index.html.
  String get boxesKey => jsonEncode(_boxes);

  /// Whether `order` was computed for the boxes as they are right now.
  bool get orderFresh => _orderFor == boxesKey;
  bool get needsNumbering => !orderFresh;
  bool get canSave => orderFresh && _order.length == _boxes.length;

  // --- boxes-step mutations ---

  void select(int k) {
    if (_step != LabelStep.boxes) return;
    _selected = k;
    notifyListeners();
  }

  void deselect() {
    if (_step != LabelStep.boxes) return;
    _selected = -1;
    notifyListeners();
  }

  void addBox(Box b) {
    if (_step != LabelStep.boxes) return;
    if (b[2] - b[0] <= 0.02 || b[3] - b[1] <= 0.02) return;
    _boxes.add(_copyBox(b));
    _kinds.add('balloon');
    _hist.add(_HistEntry(k: _boxes.length - 1, add: true));
    _selected = _boxes.length - 1;
    notifyListeners();
  }

  /// Live update during a drag; no undo entry (that's [commitDrag]).
  void moveBoxTo(int k, Box b) {
    if (_step != LabelStep.boxes) return;
    _boxes[k] = _copyBox(b);
    notifyListeners();
  }

  /// Push one undo entry for a finished drag, restoring to [original].
  void commitDrag(int k, Box original) {
    if (_step != LabelStep.boxes) return;
    _hist.add(_HistEntry(k: k, box: _copyBox(original)));
    notifyListeners();
  }

  void deleteSelected() {
    if (_step != LabelStep.boxes) return;
    final k = _selected;
    if (k < 0 || k >= _boxes.length) return;
    _hist.add(
      _HistEntry(k: k, del: true, box: _copyBox(_boxes[k]), kind: _kinds[k]),
    );
    _boxes.removeAt(k);
    _kinds.removeAt(k);
    _selected = -1;
    notifyListeners();
  }

  void toggleKind() {
    if (mode != LabelMode.balloons) return;
    if (_step != LabelStep.boxes) return;
    final k = _selected;
    if (k < 0) return;
    _hist.add(_HistEntry(k: k, kind: _kinds[k]));
    _kinds[k] = _kinds[k] == 'caption' ? 'balloon' : 'caption';
    notifyListeners();
  }

  void clear() {
    if (_step != LabelStep.boxes) return;
    if (_boxes.isEmpty) return;
    _hist.add(_HistEntry(all: _copyBoxes(_boxes), kinds: List.of(_kinds)));
    _boxes = [];
    _kinds = [];
    _selected = -1;
    notifyListeners();
  }

  /// Back to the prefill boxes, step and history reset. Works from either
  /// step (the web labeller's "Reset page" button isn't boxes-only).
  void resetToPrefill() {
    _boxes = _copyBoxes(_prefillBoxes);
    _kinds = List<String>.from(_prefillKinds);
    _order = [];
    _orderFor = null;
    _hist.clear();
    _selected = -1;
    _step = LabelStep.boxes;
    notifyListeners();
  }

  void undo() {
    if (_step != LabelStep.boxes) return;
    if (_hist.isEmpty) return;
    final h = _hist.removeLast();
    if (h.all != null) {
      _boxes = h.all!;
      _kinds = h.kinds!;
      _selected = -1;
    } else if (h.add) {
      _boxes.removeAt(h.k!);
      _kinds.removeAt(h.k!);
      _selected = -1;
    } else if (h.del) {
      _boxes.insert(h.k!, h.box!);
      _kinds.insert(h.k!, h.kind!);
      _selected = h.k!;
    } else if (h.kind != null) {
      _kinds[h.k!] = h.kind!;
      _selected = h.k!;
    } else {
      _boxes[h.k!] = h.box!;
      _selected = h.k!;
    }
    notifyListeners();
  }

  // --- order step ---

  /// Ignored if [forBoxes] no longer matches the live boxes (a reply for a
  /// numbering request whose boxes have since been edited).
  void setOrder(List<int> o, {required String forBoxes}) {
    if (forBoxes != boxesKey) return;
    _order = List<int>.from(o);
    _orderFor = forBoxes;
    notifyListeners();
  }

  void toOrderStep() {
    _step = LabelStep.order;
    _selected = -1;
    notifyListeners();
  }

  void backToBoxes() {
    _step = LabelStep.boxes;
    notifyListeners();
  }

  /// order = [], but fresh for the current boxes (nothing to re-number).
  void restartOrder() {
    _order = [];
    _orderFor = boxesKey;
    notifyListeners();
  }

  void tapOrder(int k) {
    if (_step != LabelStep.order) return;
    if (_order.contains(k)) return;
    _order.add(k);
    notifyListeners();
  }

  /// No panels/balloons on this page. Caller saves the empty body next.
  void markNone() {
    _boxes = [];
    _kinds = [];
    _order = [];
    _orderFor = boxesKey;
    _selected = -1;
    notifyListeners();
  }

  Map<String, dynamic> toSaveBody({required int w, required int h}) {
    final body = <String, dynamic>{
      'w': w,
      'h': h,
      'note': _note.trim(),
      'boxes': _boxes.map((b) => b.map(_round4).toList()).toList(),
      'order': List<int>.from(_order),
    };
    if (mode == LabelMode.balloons) {
      body['kinds'] = List<String>.from(_kinds);
    }
    return body;
  }

  static double _round4(double v) => (v * 1e4).round() / 1e4;

  // --- static geometry, ported from index.html's hit()/move/resize ---

  /// Index of the box under (x, y), or null. The [selected] box's own edge
  /// always wins; otherwise the smallest box under the point wins (so an
  /// inset isn't stolen by a bigger host under it). [skip], when given,
  /// excludes indexes from consideration entirely — the order step's own
  /// hit-test uses this to skip already-numbered boxes (JS: `hit(e,
  /// k=>order.includes(k))`), so tapping inside a numbered inset still
  /// reaches its unnumbered host underneath instead of no-oping.
  static int? hitTest(
    List<Box> boxes,
    double x,
    double y, {
    required int selected,
    required double grabX,
    required double grabY,
    bool Function(int k)? skip,
  }) {
    int? selectedEdgeHit;
    int? smallestK;
    double smallestArea = double.infinity;
    for (var k = 0; k < boxes.length; k++) {
      if (skip != null && skip(k)) continue;
      final b = boxes[k];
      if (x < b[0] - grabX ||
          x > b[2] + grabX ||
          y < b[1] - grabY ||
          y > b[3] + grabY) {
        continue;
      }
      final area = (b[2] - b[0]) * (b[3] - b[1]);
      if (area < smallestArea) {
        smallestArea = area;
        smallestK = k;
      }
      if (k == selected) {
        final e = _edgeFlags(b, x, y, grabX, grabY);
        if (e.l || e.r || e.t || e.b) selectedEdgeHit = k;
      }
    }
    return selectedEdgeHit ?? smallestK;
  }

  static ({bool l, bool r, bool t, bool b})? edgesAt(
    List<Box> boxes,
    double x,
    double y, {
    required int selected,
    required double grabX,
    required double grabY,
    bool Function(int k)? skip,
  }) {
    final k = hitTest(
      boxes,
      x,
      y,
      selected: selected,
      grabX: grabX,
      grabY: grabY,
      skip: skip,
    );
    if (k == null) return null;
    return _edgeFlags(boxes[k], x, y, grabX, grabY);
  }

  static ({bool l, bool r, bool t, bool b}) _edgeFlags(
    Box b,
    double x,
    double y,
    double grabX,
    double grabY,
  ) {
    return (
      l: (x - b[0]).abs() <= grabX,
      r: (x - b[2]).abs() <= grabX,
      t: (y - b[1]).abs() <= grabY,
      b: (y - b[3]).abs() <= grabY,
    );
  }

  /// Translate [orig] by (dx, dy), clamped so the box stays inside [0, 1].
  static Box moved(Box orig, double dx, double dy) {
    final sx = dx.clamp(-orig[0], 1 - orig[2]);
    final sy = dy.clamp(-orig[1], 1 - orig[3]);
    return [orig[0] + sx, orig[1] + sy, orig[2] + sx, orig[3] + sy];
  }

  /// Drag the edges in [ed] of [orig] to (x, y), keeping a minimum side of
  /// 0.005. Assumes (x, y) are already clamped to [0, 1] by the caller.
  static Box resized(
    Box orig,
    ({bool l, bool r, bool t, bool b}) ed,
    double x,
    double y,
  ) {
    final b = _copyBox(orig);
    if (ed.l) b[0] = math.min(x, orig[2] - 0.005);
    if (ed.r) b[2] = math.max(x, orig[0] + 0.005);
    if (ed.t) b[1] = math.min(y, orig[3] - 0.005);
    if (ed.b) b[3] = math.max(y, orig[1] + 0.005);
    return b;
  }
}
