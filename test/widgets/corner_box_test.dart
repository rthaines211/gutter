import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:comic_reader_app/config/app_theme.dart';
import 'package:comic_reader_app/config/comic_style.dart';
import 'package:comic_reader_app/config/scheme.dart';
import 'package:comic_reader_app/models/stats_summary.dart';
import 'package:comic_reader_app/providers/providers.dart';
import 'package:comic_reader_app/widgets/corner_box.dart';
import 'package:comic_reader_app/widgets/reading_stamp.dart';

const _accent = Color(0xFF0A84FF);

Future<void> _pump(WidgetTester t, Widget child,
    {ComicStyle style = ComicStyle.fullPop, Scheme scheme = Scheme.oledBlack}) async {
  SharedPreferences.setMockInitialValues({'comic_style': style.name});
  final prefs = await SharedPreferences.getInstance();
  await t.pumpWidget(ProviderScope(
    overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
    child: MaterialApp(
      theme: AppTheme.themeData(scheme),
      home: Scaffold(body: Center(child: SizedBox(width: 280, child: child))),
    ),
  ));
}

StatsSummary _summary({int pages = 1284, int issues = 31, int streak = 5}) =>
    StatsSummary.fromJson({
      'all_time': {'pages_read': 9000, 'issues_finished': 300},
      'this_week': {'pages_read': 200},
      'this_month': {'pages_read': pages, 'issues_finished': issues, 'time_read_s': 8040},
      'streak': {'current': streak, 'longest': 12},
    });

void main() {
  group('seriesRunYears', () {
    test('same century collapses the end year', () {
      expect(seriesRunYears([1975, 1979, 1977]), '1975–79');
    });
    test('across centuries keeps both in full', () {
      expect(seriesRunYears([1998, 2003]), '1998–2003');
    });
    test('single year', () {
      expect(seriesRunYears([1979, 1979]), '1979');
    });
    test('falls back to the series start year, else null', () {
      expect(seriesRunYears([null, null], fallback: 1984), '1984');
      expect(seriesRunYears(const []), isNull);
    });
    test('pads the short end year', () {
      expect(seriesRunYears([2001, 2005]), '2001–05');
    });
  });

  group('coverYear', () {
    test('reads the leading year of a cover date', () {
      expect(coverYear('1979-05-01'), 1979);
      expect(coverYear('1979'), 1979);
      expect(coverYear(null), isNull);
      expect(coverYear('n/a'), isNull);
    });
  });

  group('CornerBox', () {
    for (final style in ComicStyle.values) {
      for (final scheme in [Scheme.oledBlack, Scheme.sepiaPaper]) {
        testWidgets('series badge renders under $style / ${scheme.dark ? 'OLED' : 'sepia'}',
            (t) async {
          await _pump(
            t,
            const CornerBox(
              band: 'Series',
              bandColor: _accent,
              big: '24',
              bigCaption: 'Issues',
              stack: ['1975–79', '18 read', '6 left'],
              accent: _accent,
            ),
            style: style,
            scheme: scheme,
          );
          expect(find.text('SERIES'), findsOneWidget);
          expect(find.text('24'), findsOneWidget);
          expect(find.text('ISSUES'), findsOneWidget);
          expect(find.text('18 READ'), findsOneWidget);
          expect(t.takeException(), isNull);
        });
      }
    }
  });

  group('ReadingStamp', () {
    for (final style in ComicStyle.values) {
      testWidgets('shows this month under $style', (t) async {
        await _pump(
          t,
          ReadingStamp(summary: _summary(), accent: _accent, month: DateTime(2026, 10)),
          style: style,
        );
        expect(find.text('1,284'), findsOneWidget);
        expect(find.text('OCT'), findsOneWidget);
        expect(find.text('2026'), findsOneWidget);
        expect(find.text('31 ISSUES'), findsOneWidget);
        expect(find.text('No. 10'), findsOneWidget);
        expect(find.textContaining('2h 14m', findRichText: true), findsOneWidget);
        expect(find.textContaining('5d', findRichText: true), findsOneWidget);
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('one issue reads singular, zero pages still renders', (t) async {
      await _pump(
        t,
        ReadingStamp(summary: _summary(pages: 0, issues: 1), accent: _accent, month: DateTime(2026, 1)),
      );
      expect(find.text('1 ISSUE'), findsOneWidget);
      expect(find.text('0'), findsOneWidget);
      expect(find.text('JAN'), findsOneWidget);
    });

    test('groupThousands', () {
      expect(ReadingStamp.groupThousands(0), '0');
      expect(ReadingStamp.groupThousands(999), '999');
      expect(ReadingStamp.groupThousands(1284), '1,284');
      expect(ReadingStamp.groupThousands(1234567), '1,234,567');
    });
  });
}
