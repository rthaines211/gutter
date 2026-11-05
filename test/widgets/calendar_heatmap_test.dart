import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/models/stats_summary.dart';
import 'package:comic_reader_app/widgets/calendar_heatmap.dart';

void main() {
  group('CalendarHeatmap', () {
    test('bucketIndex returns 0 for zero pages', () {
      expect(CalendarHeatmap.bucketIndex(0), 0);
    });

    test('bucketIndex returns increasing values', () {
      expect(CalendarHeatmap.bucketIndex(3), 1);    // 1-5
      expect(CalendarHeatmap.bucketIndex(10), 2);   // 6-15
      expect(CalendarHeatmap.bucketIndex(25), 3);   // 16-40
      expect(CalendarHeatmap.bucketIndex(50), 4);   // 41+
    });

    test('bucketIndex edge cases', () {
      expect(CalendarHeatmap.bucketIndex(1), 1);
      expect(CalendarHeatmap.bucketIndex(5), 1);
      expect(CalendarHeatmap.bucketIndex(6), 2);
      expect(CalendarHeatmap.bucketIndex(15), 2);
      expect(CalendarHeatmap.bucketIndex(16), 3);
      expect(CalendarHeatmap.bucketIndex(40), 3);
      expect(CalendarHeatmap.bucketIndex(41), 4);
    });

    testWidgets('renders without crashing', (tester) async {
      final data = List.generate(
        365,
        (i) => DailyPages(date: '2026-01-01', pages: i % 50),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CalendarHeatmap(pagesPerDay: data, accent: Colors.blue),
          ),
        ),
      );

      expect(find.byType(CalendarHeatmap), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
