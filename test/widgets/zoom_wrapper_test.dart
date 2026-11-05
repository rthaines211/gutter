import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/widgets/zoom_wrapper.dart';
import 'package:comic_reader_app/services/zoom_math.dart';

void main() {
  group('ZoomWrapper', () {
    testWidgets('panEnabled when externally-set scale > 1', (tester) async {
      final controller = TransformationController();
      // Pre-set a programmatic 2x scale (spread half).
      controller.value = Matrix4.identity()..scaleByDouble(2.0, 2.0, 1.0, 1.0);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 800,
            child: ZoomWrapper(
              externalController: controller,
              displayRect: const Rect.fromLTWH(0, 0, 400, 800),
              viewportSize: const Size(400, 800),
              child: Container(color: Colors.red),
            ),
          ),
        ),
      ));

      final iv = tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
      expect(iv.panEnabled, isTrue);
    });

    testWidgets('panEnabled false when scale == 1', (tester) async {
      final controller = TransformationController();
      controller.value = Matrix4.identity();

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 800,
            child: ZoomWrapper(
              externalController: controller,
              displayRect: const Rect.fromLTWH(0, 0, 400, 800),
              viewportSize: const Size(400, 800),
              child: Container(color: Colors.red),
            ),
          ),
        ),
      ));

      final iv = tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
      expect(iv.panEnabled, isFalse);
    });

    testWidgets('boundaryMargin is zero for programmatic scale', (tester) async {
      final controller = TransformationController();
      controller.value = Matrix4.identity()..scaleByDouble(2.0, 2.0, 1.0, 1.0);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 800,
            child: ZoomWrapper(
              externalController: controller,
              displayRect: const Rect.fromLTWH(0, 0, 400, 800),
              viewportSize: const Size(400, 800),
              child: Container(color: Colors.red),
            ),
          ),
        ),
      ));

      final iv = tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
      expect(iv.boundaryMargin, EdgeInsets.zero);
    });

    test('EdgeDirection enum exported', () {
      expect(EdgeDirection.values.length, 2);
    });
  });
}
