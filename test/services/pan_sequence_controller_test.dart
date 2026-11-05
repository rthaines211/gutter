import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/services/pan_sequence_controller.dart';

void main() {
  group('PanSequenceController', () {
    Matrix4 tx(double x, double y) => Matrix4.identity()
      ..setEntry(0, 3, x)
      ..setEntry(1, 3, y);

    // 2x zoom on an 800x600 viewport: top half then bottom half.
    Matrix4 zoom2(double x, double y) => Matrix4.identity()
      ..scaleByDouble(2, 2, 1, 1)
      ..setTranslationRaw(x, y, 0);
    const viewport = Size(800, 600);

    test('jumpToNearest lands on the step showing the same spot', () {
      final controller = PanSequenceController();
      controller.setTransforms([zoom2(-400, 0), zoom2(-400, -600)]);
      // Was looking at the bottom of the page at a different zoom.
      controller.jumpToNearest(
        Matrix4.identity()
          ..scaleByDouble(1.5, 1.5, 1, 1)
          ..setTranslationRaw(-200, -300, 0),
        viewport,
      );
      expect(controller.currentIndex, 1);
    });

    test('jumpToNearest keeps the top step for a top view', () {
      final controller = PanSequenceController();
      controller.setTransforms([zoom2(-400, 0), zoom2(-400, -600)]);
      controller.jumpToNearest(Matrix4.identity(), viewport);
      expect(controller.currentIndex, 0);
    });

    test('starts at index 0', () {
      final controller = PanSequenceController();
      controller.setTransforms([Matrix4.identity(), tx(10, 0)]);
      expect(controller.currentIndex, 0);
    });

    test('advance moves to next transform', () {
      final controller = PanSequenceController();
      controller.setTransforms([Matrix4.identity(), tx(10, 0), tx(20, 0)]);
      final result = controller.advance();
      expect(result, PanResult.viewportChanged);
      expect(controller.currentIndex, 1);
    });

    test('advance at last transform returns sequenceEnd', () {
      final controller = PanSequenceController();
      controller.setTransforms([Matrix4.identity()]);
      final result = controller.advance();
      expect(result, PanResult.sequenceEnd);
    });

    test('retreat at first transform returns sequenceStart', () {
      final controller = PanSequenceController();
      controller.setTransforms([Matrix4.identity(), tx(10, 0)]);
      final result = controller.retreat();
      expect(result, PanResult.sequenceStart);
    });

    test('retreat from middle moves backward', () {
      final controller = PanSequenceController();
      controller.setTransforms([Matrix4.identity(), tx(10, 0), tx(20, 0)]);
      controller.advance();
      controller.advance();
      final result = controller.retreat();
      expect(result, PanResult.viewportChanged);
      expect(controller.currentIndex, 1);
    });

    test('reset sets index to 0', () {
      final controller = PanSequenceController();
      controller.setTransforms([Matrix4.identity(), tx(10, 0)]);
      controller.advance();
      controller.reset();
      expect(controller.currentIndex, 0);
    });

    test('jumpToEnd sets index to last', () {
      final controller = PanSequenceController();
      controller.setTransforms([Matrix4.identity(), tx(10, 0), tx(20, 0)]);
      controller.jumpToEnd();
      expect(controller.currentIndex, 2);
    });

    test('currentTransform returns correct matrix', () {
      final controller = PanSequenceController();
      final target = tx(42, 0);
      controller.setTransforms([Matrix4.identity(), target]);
      controller.advance();
      expect(controller.currentTransform, target);
    });

    test('empty transforms: advance returns sequenceEnd', () {
      final controller = PanSequenceController();
      expect(controller.advance(), PanResult.sequenceEnd);
    });

    test('hasMultipleSteps is false for single transform', () {
      final controller = PanSequenceController();
      controller.setTransforms([Matrix4.identity()]);
      expect(controller.hasMultipleSteps, false);
    });

    test('hasMultipleSteps is true for multiple transforms', () {
      final controller = PanSequenceController();
      controller.setTransforms([Matrix4.identity(), tx(10, 0)]);
      expect(controller.hasMultipleSteps, true);
    });
  });
  test('notifies listeners when the step changes', () {
    final c = PanSequenceController();
    var n = 0;
    c.addListener(() => n++);
    c.setTransforms([Matrix4.identity(), Matrix4.identity()]);
    c.advance();
    c.advance(); // at end: no change, no notify
    c.retreat();
    c.jumpToEnd();
    c.reset();
    expect(n, 5);
  });
}
