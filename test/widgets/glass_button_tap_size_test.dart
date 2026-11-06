import 'package:comic_reader_app/widgets/glass_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('GlassButton takes taps over 44pt while drawing 36pt', (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      home: Center(child: GlassButton(onTap: () => taps++, child: const Icon(Icons.close))),
    ));
    final box = tester.getRect(find.byType(GlassButton));
    expect(box.size, const Size(44, 44));
    await tester.tapAt(box.topLeft + const Offset(1, 1)); // outside the 36pt glass
    expect(taps, 1);
  });
}
