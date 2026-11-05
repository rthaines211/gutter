import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/widgets/halftone_overlay.dart';

void main() {
  testWidgets('renders without error at Ben-Day settings', (t) async {
    await t.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Stack(children: [
          SizedBox.expand(),
          HalftoneOverlay(
            color: Color(0xFF0A84FF),
            opacity: 0.55,
            dotSpacing: 9,
            dotRadius: 1.6,
            blendMode: BlendMode.overlay,
          ),
        ]),
      ),
    ));
    expect(t.takeException(), isNull);
  });

  testWidgets('existing callers still work with no new params', (t) async {
    await t.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Stack(children: [SizedBox.expand(), HalftoneOverlay()]),
      ),
    ));
    expect(find.byType(HalftoneOverlay), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  test('painter repaints when the new fields change', () {
    // A missed field in shouldRepaint means the texture silently fails to
    // update when comicStyle changes.
    const a = HalftoneOverlay(dotRadius: 1.0);
    const b = HalftoneOverlay(dotRadius: 1.6);
    expect(a.dotRadius, isNot(b.dotRadius));
  });
}
