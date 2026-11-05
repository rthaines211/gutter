import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:comic_reader_app/widgets/liquid_glass.dart';

Widget _wrap(Widget child) =>
    ProviderScope(child: MaterialApp(home: Scaffold(body: child)));

void main() {
  group('LiquidGlass', () {
    testWidgets('renders child inside a BackdropFilter', (tester) async {
      await tester.pumpWidget(_wrap(const LiquidGlass(child: Text('Hello'))));
      await tester.pump();
      expect(find.text('Hello'), findsOneWidget);
      expect(find.byType(BackdropFilter), findsOneWidget);
    });

    testWidgets('accepts custom radius and intensity', (tester) async {
      await tester.pumpWidget(_wrap(const LiquidGlass(
        radius: 30,
        intensity: 40,
        child: SizedBox(width: 100, height: 100),
      )));
      await tester.pump();
      expect(find.byType(LiquidGlass), findsOneWidget);
    });
  });
}
