import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/widgets/panel_dim_overlay.dart';

void main() {
  testWidgets('dims with a hole when given one, fades out without', (tester) async {
    await tester.pumpWidget(const Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(children: [PanelDimOverlay(hole: Rect.fromLTWH(10, 10, 50, 50))]),
    ));
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity, 1);
    final painter = tester.widget<CustomPaint>(find.byType(CustomPaint)).painter as PanelDimPainter;
    expect(painter.hole, const Rect.fromLTWH(10, 10, 50, 50));
    expect(find.byType(IgnorePointer), findsOneWidget);

    await tester.pumpWidget(const Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(children: [PanelDimOverlay(hole: null)]),
    ));
    expect(tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity, 0);
  });

  test('painter repaints only when the hole moves', () {
    const a = PanelDimPainter(Rect.fromLTWH(0, 0, 1, 1));
    expect(a.shouldRepaint(const PanelDimPainter(Rect.fromLTWH(0, 0, 1, 1))), isFalse);
    expect(a.shouldRepaint(const PanelDimPainter(Rect.fromLTWH(0, 0, 2, 2))), isTrue);
  });
}
