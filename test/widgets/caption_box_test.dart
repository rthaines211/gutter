import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/config/comic_style.dart';
import 'package:comic_reader_app/config/scheme.dart';
import 'package:comic_reader_app/widgets/caption_box.dart';

const _accent = Color(0xFF0A84FF);
ComicTokens _tokens(ComicStyle s) =>
    ComicTokens.of(s, Scheme.sepiaPaper, _accent);

Future<void> _pump(WidgetTester t, ComicStyle style,
        {bool rightSide = false}) =>
    t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CaptionBox(
          text: 'CONTINUE',
          comic: _tokens(style),
          rightSide: rightSide,
        ),
      ),
    ));

void main() {
  testWidgets('renders its text in every style', (t) async {
    for (final s in ComicStyle.values) {
      await _pump(t, s);
      expect(find.text('CONTINUE'), findsOneWidget);
    }
  });

  testWidgets('fullPop uses the yellow caption, not a pill', (t) async {
    await _pump(t, ComicStyle.fullPop);
    final box = t.widget<Container>(find.byType(Container).first);
    final d = box.decoration as BoxDecoration;
    expect(d.color, const Color(0xFFFFE14D));
    expect((d.borderRadius as BorderRadius).topLeft.x, 3);
  });

  testWidgets('off uses a dark pill', (t) async {
    await _pump(t, ComicStyle.off);
    final box = t.widget<Container>(find.byType(Container).first);
    final d = box.decoration as BoxDecoration;
    expect(d.color, const Color(0x73000000));
    expect((d.borderRadius as BorderRadius).topLeft.x, greaterThan(100));
  });

  testWidgets('fullPop tilts, and right-side tags tilt the other way',
      (t) async {
    // Scoped to CaptionBox's own Transform: Scaffold/MaterialApp chrome adds
    // ambient Transform widgets of its own (see the no-tilt test below), so a
    // bare `find.byType(Transform).first` would be fragile — correct only by
    // accident of document order.
    final captionTransform = find.descendant(
      of: find.byType(CaptionBox),
      matching: find.byType(Transform),
    );

    await _pump(t, ComicStyle.fullPop);
    final left = t.widget<Transform>(captionTransform);
    await _pump(t, ComicStyle.fullPop, rightSide: true);
    final right = t.widget<Transform>(captionTransform);
    // Opposite signs — one tilts left, the other right.
    expect(left.transform.storage[1] * right.transform.storage[1],
        lessThan(0));
  });

  testWidgets('non-fullPop styles do not tilt', (t) async {
    await _pump(t, ComicStyle.off);
    // Scoped to CaptionBox's own subtree: Scaffold/MaterialApp chrome
    // contains ambient Transform widgets (e.g. RotationTransition internals)
    // unrelated to this widget, so a bare `find.byType(Transform)` is not a
    // valid probe here — it would fail even with no CaptionBox in the tree.
    expect(
      find.descendant(
        of: find.byType(CaptionBox),
        matching: find.byType(Transform),
      ),
      findsNothing,
    );
  });
}
