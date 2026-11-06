import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/config/comic_style.dart';
import 'package:comic_reader_app/config/scheme.dart';
import 'package:comic_reader_app/models/stats_summary.dart';
import 'package:comic_reader_app/widgets/this_week_card.dart';

const _accent = Color(0xFF0A84FF);
final _comic = ComicTokens.of(ComicStyle.off, Scheme.oledBlack, _accent);

/// Builds a DailyPages list ending today, going back [count] days (oldest
/// first), so the last entry is always "today" — matches the
/// DateTime.tryParse + day-difference convention used by
/// StatsStrip._computeStreak.
List<DailyPages> _daysEndingToday(List<int> pagesOldestFirst) {
  final now = DateTime.now();
  final n = pagesOldestFirst.length;
  return List.generate(n, (i) {
    final daysAgo = n - 1 - i;
    final date = now.subtract(Duration(days: daysAgo));
    final dateStr =
        '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    return DailyPages(date: dateStr, pages: pagesOldestFirst[i]);
  });
}

Future<void> _pump(WidgetTester t, List<DailyPages> pagesPerDay) =>
    t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ThisWeekCard(
          pagesPerDay: pagesPerDay,
          comic: _comic,
          accent: _accent,
        ),
      ),
    ));

void main() {
  group('ThisWeekCard', () {
    testWidgets('one page reads "1 page", not "1 pages"', (t) async {
      await _pump(t, _daysEndingToday([0, 0, 0, 0, 0, 0, 1]));
      expect(find.text('1 page'), findsOneWidget);
      await _pump(t, _daysEndingToday([0, 0, 0, 0, 0, 1, 1]));
      expect(find.text('2 pages'), findsOneWidget);
    });

    testWidgets('renders exactly 7 bars for a full 7-day week', (t) async {
      await _pump(t, _daysEndingToday([1, 2, 3, 4, 5, 6, 7]));
      expect(find.byKey(const ValueKey('this_week_bar')), findsNWidgets(7));
    });

    testWidgets('renders exactly 7 bars when given fewer than 7 days',
        (t) async {
      await _pump(t, _daysEndingToday([3, 5]));
      expect(find.byKey(const ValueKey('this_week_bar')), findsNWidgets(7));
    });

    testWidgets('renders exactly 7 bars when given more than 7 days',
        (t) async {
      await _pump(t, _daysEndingToday(List.generate(30, (i) => i)));
      expect(find.byKey(const ValueKey('this_week_bar')), findsNWidgets(7));
    });

    testWidgets('renders exactly 7 bars for an empty list without throwing',
        (t) async {
      await _pump(t, const []);
      expect(find.byKey(const ValueKey('this_week_bar')), findsNWidgets(7));
      expect(t.takeException(), isNull);
    });

    testWidgets('all-zero week renders without dividing by zero', (t) async {
      await _pump(t, _daysEndingToday([0, 0, 0, 0, 0, 0, 0]));
      expect(find.byKey(const ValueKey('this_week_bar')), findsNWidgets(7));
      expect(t.takeException(), isNull);
    });

    testWidgets('today and the best day get solid accent; others get 55%',
        (t) async {
      // oldest..newest: [1, 2, 8, 1, 1, 1, 4] -> best day is index 2 (8),
      // today is the last entry (4). Both should be solid accent.
      // The rest (indices 0,1,3,4,5 with pages>0) should be accent@55%.
      await _pump(t, _daysEndingToday([1, 2, 8, 1, 1, 1, 4]));

      final containers = t
          .widgetList<Container>(find.byKey(const ValueKey('this_week_bar')))
          .toList();
      expect(containers.length, 7);

      Color colorOf(Container c) => (c.decoration as BoxDecoration).color!;

      // best day (index 2, value 8) — solid accent
      expect(colorOf(containers[2]), _accent);
      // today (index 6, value 4) — solid accent
      expect(colorOf(containers[6]), _accent);
      // an active but non-best, non-today day — accent at 55%
      expect(colorOf(containers[0]), _accent.withValues(alpha: 0.55));
    });

    testWidgets('zero-page days render scheme.s3', (t) async {
      await _pump(t, _daysEndingToday([0, 3, 0, 0, 0, 0, 2]));
      final containers = t
          .widgetList<Container>(find.byKey(const ValueKey('this_week_bar')))
          .toList();
      final color = (containers[0].decoration as BoxDecoration).color!;
      expect(color, Scheme.oledBlack.s3);
    });

    testWidgets('shows total pages figure', (t) async {
      await _pump(t, _daysEndingToday([1, 2, 3, 4, 5, 6, 7]));
      // Sum of the 7 days = 28.
      expect(find.textContaining('28'), findsOneWidget);
    });

    testWidgets('renders without throwing when only one day is provided',
        (t) async {
      await _pump(t, _daysEndingToday([5]));
      expect(t.takeException(), isNull);
      expect(find.byKey(const ValueKey('this_week_bar')), findsNWidgets(7));
    });
  });
}
