import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/widgets/progress_bar.dart';

void main() {
  group('ProgressBar', () {
    testWidgets('renders with default color', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ProgressBar(value: 0.5),
          ),
        ),
      );
      expect(find.byType(ProgressBar), findsOneWidget);
    });

    testWidgets('renders with custom color', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ProgressBar(
              value: 0.75,
              color: Colors.red,
              height: 6,
            ),
          ),
        ),
      );
      expect(find.byType(ProgressBar), findsOneWidget);
    });

    testWidgets('clamps value to 0-1 range', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ProgressBar(value: 1.5),
          ),
        ),
      );
      expect(find.byType(ProgressBar), findsOneWidget);
    });
  });
}
