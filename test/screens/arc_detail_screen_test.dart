import 'package:comic_reader_app/models/arc.dart';
import 'package:comic_reader_app/models/series.dart';
import 'package:comic_reader_app/providers/arc_provider.dart';
import 'package:comic_reader_app/providers/providers.dart';
import 'package:comic_reader_app/screens/arc_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _longDescription =
    'Bane has taken control of Gotham City and Batman has been driven out. '
    'With the Dark Knight gone, Bane’s forces patrol the streets while Bruce '
    'Wayne plans his return to reclaim the city and confront the man who '
    'broke him. Meanwhile the Flashpoint Batman stalks the rooftops, and '
    'every ally Bruce has left is scattered across the world, waiting for a '
    'signal that may never come. The city holds its breath.';

Arc _arc({String description = '', int present = 11}) => Arc(
      id: 'arc1',
      name: '"Batman" City of Bane',
      imageUrl: '',
      selfContained: true,
      total: 0,
      present: present,
      source: 'comicvine',
      publisher: 'DC Comics',
      startYear: 2019,
      endYear: 2020,
      read: 4,
      coverUrl: '',
      lastReadAt: null,
      description: description,
    );

/// [count] issues numbered from 75; the first [completed] are read and the
/// next one is in progress.
List<SeriesIssue> _issues(int count, {int completed = 4}) => [
      for (var i = 0; i < count; i++)
        SeriesIssue(
          id: 'c$i',
          name: 'Batman ${75 + i}.cbz',
          number: '${75 + i}',
          coverUrl: '',
          status: i < completed
              ? 'completed'
              : (i == completed ? 'in_progress' : 'unread'),
          currentPage: i == completed ? 12 : null,
          totalPages: i == completed ? 24 : null,
          title: 'City of Bane Part ${i + 1}',
          coverDate: '2019-09-01',
          seriesId: 's1',
          seriesName: 'Batman (2016)',
        ),
    ];

Future<void> _pump(
  WidgetTester t,
  Size size,
  Arc arc,
  List<SeriesIssue> issues,
) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        arcIssuesProvider.overrideWith((ref, id) => Stream.value(issues)),
      ],
      child: MaterialApp(home: ArcDetailScreen(arc: arc)),
    ),
  );
  await t.pump();
  await t.pump(const Duration(milliseconds: 100));
}

Finder get _scrollable => find.byType(Scrollable).first;

void main() {
  for (final size in const [Size(1024, 1366), Size(390, 844)]) {
    testWidgets('header, summary, chips and rows at $size', (t) async {
      await _pump(t, size, _arc(description: _longDescription), _issues(11));

      expect(find.text('City of Bane'), findsOneWidget);
      expect(find.text('BATMAN'), findsOneWidget);
      expect(find.text('DC COMICS · 2019–20 · 11 ISSUES'), findsOneWidget);
      expect(find.text('READ 4 OF 11'), findsOneWidget);
      expect(find.text('Continue #79'), findsOneWidget);
      expect(find.text('More'), findsOneWidget);
      expect(find.text('Batman (2016)'), findsOneWidget);
      expect(find.text('Show all 11 issues'), findsNothing);

      await t.tap(find.text('More'));
      await t.pump();
      expect(find.text('Less'), findsOneWidget);

      await t.scrollUntilVisible(find.text('Batman #79'), 300,
          scrollable: _scrollable);
      expect(find.text('P.12 / 24'), findsOneWidget);
      expect(find.text('SEP 2019'), findsWidgets);
    });

    testWidgets('67-issue arc pages a 20-issue window at $size', (t) async {
      await _pump(t, size, _arc(present: 67), _issues(67, completed: 7));

      expect(find.text('6–25 OF 67'), findsOneWidget);
      await t.scrollUntilVisible(find.text('Show all 67 issues'), 300,
          scrollable: _scrollable);
      expect(find.text('25'), findsOneWidget);
      expect(find.text('26'), findsNothing);
      expect(find.text('05'), findsNothing);

      await t.tap(find.text('Show all 67 issues'));
      await t.pump();
      expect(find.text('Show all 67 issues'), findsNothing);
      await t.scrollUntilVisible(find.text('67'), 300, scrollable: _scrollable);
      expect(find.text('Batman #141'), findsOneWidget);
    });
  }

  testWidgets('no description hides the summary; fresh arc says Start reading',
      (t) async {
    await _pump(t, const Size(1024, 1366), _arc(), _issues(3, completed: -1)
        .map((i) => SeriesIssue(
              id: i.id,
              name: i.name,
              number: i.number,
              coverUrl: '',
              status: 'unread',
              seriesId: 's1',
              seriesName: 'Batman (2016)',
            ))
        .toList());

    expect(find.text('More'), findsNothing);
    expect(find.text('Start reading'), findsOneWidget);
    expect(find.text('Show all 3 issues'), findsNothing);
  });

  testWidgets('all read says Read again', (t) async {
    await _pump(t, const Size(390, 844), _arc(), _issues(3, completed: 3));
    expect(find.text('Read again'), findsOneWidget);
  });

  testWidgets('series chip falls back to Unknown series', (t) async {
    await _pump(t, const Size(390, 844), _arc(), const [
      SeriesIssue(
          id: 'c0', name: 'x.cbz', number: '1', coverUrl: '', status: 'unread',
          seriesId: 's9'),
    ]);
    expect(find.text('Unknown series'), findsOneWidget);
  });
}
