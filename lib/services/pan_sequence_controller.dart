import 'package:flutter/material.dart';

enum PanResult {
  viewportChanged,
  sequenceEnd,
  sequenceStart,
}

class PanSequenceController extends ChangeNotifier {
  List<Matrix4> _transforms = [];
  int _index = 0;

  void setTransforms(List<Matrix4> transforms) {
    _transforms = transforms;
    _index = 0;
    notifyListeners();
  }

  int get currentIndex => _index;

  Matrix4 get currentTransform =>
      _transforms.isNotEmpty ? _transforms[_index] : Matrix4.identity();

  bool get hasMultipleSteps => _transforms.length > 1;

  PanResult advance() {
    if (_transforms.isEmpty || _index >= _transforms.length - 1) {
      return PanResult.sequenceEnd;
    }
    _index++;
    notifyListeners();
    return PanResult.viewportChanged;
  }

  PanResult retreat() {
    if (_transforms.isEmpty || _index <= 0) {
      return PanResult.sequenceStart;
    }
    _index--;
    notifyListeners();
    return PanResult.viewportChanged;
  }

  void reset() {
    _transforms = [];
    _index = 0;
    notifyListeners();
  }

  /// Moves to the step whose view centre is closest to the page point that
  /// [previous] had at the centre of [viewport]: after the steps are rebuilt
  /// (fit, direction, zoom mode, rotation), you stay where you were reading.
  void jumpToNearest(Matrix4 previous, Size viewport) {
    if (_transforms.length < 2) return;
    final centre = viewport.center(Offset.zero);
    Offset pageAt(Matrix4 m) =>
        MatrixUtils.transformPoint(Matrix4.inverted(m), centre);
    final target = pageAt(previous);
    var best = 0;
    for (var i = 1; i < _transforms.length; i++) {
      if ((pageAt(_transforms[i]) - target).distance <
          (pageAt(_transforms[best]) - target).distance) {
        best = i;
      }
    }
    if (best != _index) {
      _index = best;
      notifyListeners();
    }
  }

  void jumpToEnd() {
    if (_transforms.isNotEmpty) {
      _index = _transforms.length - 1;
      notifyListeners();
    }
  }
}
