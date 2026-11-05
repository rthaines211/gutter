import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/widgets/longbox_mark.dart';

const _accent = Color(0xFF0A84FF);

Future<void> _pump(WidgetTester t, {Color? background, double size = 32}) =>
    t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: LongboxMark(size: size, accent: _accent, background: background),
        ),
      ),
    ));

void main() {
  testWidgets('renders at the requested size', (t) async {
    await _pump(t, size: 48);
    expect(t.getSize(find.byType(LongboxMark)), const Size(48, 48));
    expect(t.takeException(), isNull);
  });

  testWidgets('renders with no background tile', (t) async {
    // Used inline on an existing surface, e.g. beside the wordmark.
    await _pump(t);
    expect(t.takeException(), isNull);
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('survives a very small size', (t) async {
    // The rail draws it at 32; a favicon-ish size must not throw.
    await _pump(t, size: 12, background: const Color(0xFF1B1720));
    expect(t.takeException(), isNull);
  });

  test('repaints when the accent changes', () {
    // The pulled spine takes the live accent, so a stale painter would show
    // the previous colour after the user switches accents.
    const a = LongboxMark(size: 32, accent: Color(0xFF0A84FF));
    const b = LongboxMark(size: 32, accent: Color(0xFFFF3B30));
    expect(a.accent, isNot(b.accent));
  });
}
