import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:comic_reader_app/config/app_theme.dart';
import 'package:comic_reader_app/config/scheme.dart';
import 'package:comic_reader_app/models/series.dart';
import 'package:comic_reader_app/providers/providers.dart';
import 'package:comic_reader_app/widgets/series_stat_tiles.dart';

SeriesIssue _issue({
  String id = 'issue-1',
  String status = 'unread',
  int? currentPage,
  int? totalPages,
}) {
  return SeriesIssue(
    id: id,
    name: 'Issue One',
    number: '1',
    coverUrl: '',
    status: status,
    currentPage: currentPage,
    totalPages: totalPages,
  );
}

Future<void> _pump(WidgetTester t, Widget child) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await t.pumpWidget(ProviderScope(
    overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
    child: MaterialApp(
      theme: AppTheme.themeData(Scheme.oledBlack),
      home: Scaffold(body: child),
    ),
  ));
}

void main() {
  group('NextUpCard', () {
    testWidgets('in-progress issue shows page progress and Resume', (t) async {
      // currentPage=11 (0-indexed) -> "Page 12 of 28". Pages left = 28-11-1
      // = 16 -> formatMinutesLeft(16) = ceil(16*0.5) = 8 min.
      await _pump(
        t,
        NextUpCard(
          issue: _issue(status: 'in_progress', currentPage: 11, totalPages: 28),
          accent: AppTheme.accent,
          onTap: () {},
        ),
      );

      expect(find.text('CONTINUE'), findsOneWidget);
      expect(find.text('Page 12 of 28 · 8 min left'), findsOneWidget);
      expect(find.text('Resume'), findsOneWidget);
    });

    testWidgets('unread issue shows total pages and estimate, and Read label', (t) async {
      await _pump(
        t,
        NextUpCard(
          issue: _issue(status: 'unread', totalPages: 28),
          accent: AppTheme.accent,
          onTap: () {},
        ),
      );

      expect(find.text('UP NEXT'), findsOneWidget);
      expect(find.text('28 pages · ~14 min left'), findsOneWidget);
      expect(find.text('Read'), findsOneWidget);
    });

    testWidgets('tapping the card invokes onTap', (t) async {
      var tapped = false;
      await _pump(
        t,
        NextUpCard(
          issue: _issue(status: 'unread', totalPages: 10),
          accent: AppTheme.accent,
          onTap: () => tapped = true,
        ),
      );

      await t.tap(find.byType(NextUpCard));
      expect(tapped, isTrue);
    });
  });

  group('SeriesStatTiles', () {
    SeriesDetail detail({required int issueCount, required int readCount, List<SeriesIssue> issues = const []}) {
      return SeriesDetail(
        id: 's1',
        name: 'Test Series',
        folderPath: '/x',
        issueCount: issueCount,
        readCount: readCount,
        coverUrl: '',
        issues: issues,
      );
    }

    testWidgets('shows ISSUES tile with read/total counts', (t) async {
      await _pump(t, SeriesStatTiles(detail: detail(issueCount: 72, readCount: 60)));
      expect(find.text('ISSUES'), findsOneWidget);
      expect(find.text('60/72'), findsOneWidget);
    });

    testWidgets('shows TO FINISH tile derived from unread issues total pages', (t) async {
      final issues = [
        _issue(id: 'a', status: 'completed', totalPages: 20),
        _issue(id: 'b', status: 'unread', totalPages: 24),
        _issue(id: 'c', status: 'in_progress', currentPage: 5, totalPages: 24),
      ];
      // Remaining pages: unread issue b = 24 full pages, in_progress issue c
      // has 24 - 5 - 1 = 18 pages left. Total = 42 pages -> ceil(42*0.5)=21 min.
      await _pump(t, SeriesStatTiles(detail: detail(issueCount: 3, readCount: 1, issues: issues)));
      expect(find.text('TO FINISH'), findsOneWidget);
      expect(find.text('21 min left'), findsOneWidget);
    });

    testWidgets('does not show unbacked TIME READ or LAST READ tiles', (t) async {
      await _pump(t, SeriesStatTiles(detail: detail(issueCount: 5, readCount: 2)));
      expect(find.text('TIME READ'), findsNothing);
      expect(find.text('LAST READ'), findsNothing);
    });
  });
}
