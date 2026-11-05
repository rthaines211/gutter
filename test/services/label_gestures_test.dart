import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/services/label_gestures.dart';

void main() {
  group('TwoFingerGesture.classifyTwoFinger', () {
    test('scaleChange > 0.08 returns pinch', () {
      final result = classifyTwoFinger(
        held: Duration(milliseconds: 100),
        centroidDelta: Offset.zero,
        scaleChange: 0.09,
      );
      expect(result, TwoFingerGesture.pinch);
    });

    test('scaleChange == 0.08 does not return pinch', () {
      final result = classifyTwoFinger(
        held: Duration(milliseconds: 100),
        centroidDelta: Offset.zero,
        scaleChange: 0.08,
      );
      expect(result, isNot(TwoFingerGesture.pinch));
    });

    test('|dx| >= 80 && |dx| > 2*|dy| with dx < 0 returns nextPage', () {
      final result = classifyTwoFinger(
        held: Duration(milliseconds: 100),
        centroidDelta: Offset(-80, 10),
        scaleChange: 0.01,
      );
      expect(result, TwoFingerGesture.nextPage);
    });

    test('|dx| >= 80 && |dx| > 2*|dy| with dx > 0 returns prevPage', () {
      final result = classifyTwoFinger(
        held: Duration(milliseconds: 100),
        centroidDelta: Offset(80, 10),
        scaleChange: 0.01,
      );
      expect(result, TwoFingerGesture.prevPage);
    });

    test('|dx| = 79 does not return page swipe', () {
      final result = classifyTwoFinger(
        held: Duration(milliseconds: 100),
        centroidDelta: Offset(-79, 10),
        scaleChange: 0.01,
      );
      expect(result, isNot(TwoFingerGesture.nextPage));
      expect(result, isNot(TwoFingerGesture.prevPage));
    });

    test('|dx| >= 80 but |dx| <= 2*|dy| does not return page swipe', () {
      final result = classifyTwoFinger(
        held: Duration(milliseconds: 100),
        centroidDelta: Offset(-80, 50),
        scaleChange: 0.01,
      );
      expect(result, isNot(TwoFingerGesture.nextPage));
      expect(result, isNot(TwoFingerGesture.prevPage));
    });

    test('held <= 250ms && centroid moved < 12 returns undo', () {
      final result = classifyTwoFinger(
        held: Duration(milliseconds: 250),
        centroidDelta: Offset(5, 5),
        scaleChange: 0.01,
      );
      expect(result, TwoFingerGesture.undo);
    });

    test('held = 251ms does not return undo', () {
      final result = classifyTwoFinger(
        held: Duration(milliseconds: 251),
        centroidDelta: Offset(5, 5),
        scaleChange: 0.01,
      );
      expect(result, isNot(TwoFingerGesture.undo));
    });

    test('centroid moved = 12 does not return undo', () {
      final result = classifyTwoFinger(
        held: Duration(milliseconds: 250),
        centroidDelta: Offset(12, 0),
        scaleChange: 0.01,
      );
      expect(result, isNot(TwoFingerGesture.undo));
    });

    test('no rule matched returns none', () {
      final result = classifyTwoFinger(
        held: Duration(milliseconds: 500),
        centroidDelta: Offset(5, 5),
        scaleChange: 0.01,
      );
      expect(result, TwoFingerGesture.none);
    });
  });

  group('TapAction.onTap', () {
    test('same box tapped again within 300ms returns delete', () {
      final resolver = TapResolver();
      final result = resolver.onTap(
        hitBox: 1,
        selected: 1,
        sinceLastTap: Duration(milliseconds: 250),
        lastTapBox: 1,
        balloons: false,
      );
      expect(result, TapAction.delete);
    });

    test('same box tapped again at 301ms returns toggleKind if balloons', () {
      final resolver = TapResolver();
      final result = resolver.onTap(
        hitBox: 1,
        selected: 1,
        sinceLastTap: Duration(milliseconds: 301),
        lastTapBox: 1,
        balloons: true,
      );
      expect(result, TapAction.toggleKind);
    });

    test('same box tapped again at 301ms returns null if no balloons', () {
      final resolver = TapResolver();
      final result = resolver.onTap(
        hitBox: 1,
        selected: 1,
        sinceLastTap: Duration(milliseconds: 301),
        lastTapBox: 1,
        balloons: false,
      );
      expect(result, isNull);
    });

    test('tap on empty (null hitBox) returns deselect', () {
      final resolver = TapResolver();
      final result = resolver.onTap(
        hitBox: null,
        selected: 1,
        sinceLastTap: Duration(milliseconds: 500),
        lastTapBox: null,
        balloons: false,
      );
      expect(result, TapAction.deselect);
    });

    test('tap on unselected box returns select', () {
      final resolver = TapResolver();
      final result = resolver.onTap(
        hitBox: 2,
        selected: 1,
        sinceLastTap: Duration(milliseconds: 500),
        lastTapBox: null,
        balloons: false,
      );
      expect(result, TapAction.select);
    });

    test('tap on selected box with balloons returns toggleKind', () {
      final resolver = TapResolver();
      final result = resolver.onTap(
        hitBox: 1,
        selected: 1,
        sinceLastTap: Duration(milliseconds: 500),
        lastTapBox: null,
        balloons: true,
      );
      expect(result, TapAction.toggleKind);
    });

    test('tap on selected box without balloons returns null', () {
      final resolver = TapResolver();
      final result = resolver.onTap(
        hitBox: 1,
        selected: 1,
        sinceLastTap: Duration(milliseconds: 500),
        lastTapBox: null,
        balloons: false,
      );
      expect(result, isNull);
    });

    test('tap on unselected box (nothing currently selected) returns select', () {
      final resolver = TapResolver();
      final result = resolver.onTap(
        hitBox: 2,
        selected: 0,
        sinceLastTap: Duration(milliseconds: 500),
        lastTapBox: null,
        balloons: false,
      );
      expect(result, TapAction.select);
    });
  });

  group('OneFingerIntent.intentFor', () {
    test('selected box edge returns resize', () {
      final result = intentFor(
        zoomed: true,
        hitBox: 1,
        onEdge: true,
        selected: 1,
      );
      expect(result, OneFingerIntent.resize);
    });

    test('inside selected box returns move', () {
      final result = intentFor(
        zoomed: true,
        hitBox: 1,
        onEdge: false,
        selected: 1,
      );
      expect(result, OneFingerIntent.move);
    });

    test('zoomed drag on unselected box returns draw', () {
      final result = intentFor(
        zoomed: true,
        hitBox: 2,
        onEdge: false,
        selected: 1,
      );
      expect(result, OneFingerIntent.draw);
    });

    test('zoomed drag on empty returns pan', () {
      final result = intentFor(
        zoomed: true,
        hitBox: null,
        onEdge: false,
        selected: 1,
      );
      expect(result, OneFingerIntent.pan);
    });

    test('not zoomed drag on unselected box returns draw', () {
      final result = intentFor(
        zoomed: false,
        hitBox: 2,
        onEdge: false,
        selected: 1,
      );
      expect(result, OneFingerIntent.draw);
    });

    test('not zoomed drag on empty returns draw', () {
      final result = intentFor(
        zoomed: false,
        hitBox: null,
        onEdge: false,
        selected: 1,
      );
      expect(result, OneFingerIntent.draw);
    });
  });
}
