import 'package:comic_reader_app/models/arc.dart';
import 'package:comic_reader_app/models/series.dart';
import 'package:comic_reader_app/providers/arc_provider.dart';
import 'package:comic_reader_app/providers/connectivity_provider.dart';
import 'package:comic_reader_app/providers/mirror_provider.dart';
import 'package:comic_reader_app/providers/providers.dart';
import 'package:comic_reader_app/providers/read_tab_provider.dart';
import 'package:comic_reader_app/screens/read_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Online extends ConnectivityNotifier {
  @override
  bool build() => true;
}

Arc _arc(String id, String name, String source) => Arc(
      id: id, name: name, imageUrl: '', selfContained: null, total: 0,
      present: 3, source: source, publisher: '', startYear: 0, endYear: 0,
      read: 0, coverUrl: '', lastReadAt: null);

SeriesIssue _i(String id, String n, String status) => SeriesIssue(
      id: id, name: 'f$n.cbz', number: n, coverUrl: '', status: status,
      seriesId: 's', seriesName: 'Ultimates');

void main() {
  testWidgets('a user arc gets a shelf that starts at the next unread issue',
      (t) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final issues = {
      'mine': [_i('a', '19', 'completed'), _i('b', '20', 'unread'), _i('c', '21', 'unread')],
      'done': [_i('d', '1', 'completed')],
      'mylar': [_i('e', '5', 'unread')],
    };
    await t.pumpWidget(ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        connectivityProvider.overrideWith(_Online.new),
        isCustomSourceProvider.overrideWithValue(true),
        issueCoverPathsProvider.overrideWith((ref) => Stream.value(const {})),
        readTabProvider.overrideWith((ref) => Stream.value(
            const ReadTabData(continueReading: [], recentSeries: []))),
        arcsProvider.overrideWith((ref) => Stream.value([
              _arc('mine', 'Ultimate Endgame', 'user'),
              _arc('done', 'Finished Order', 'user'),
              _arc('mylar', 'Imported Event', 'mylar'),
            ])),
        arcIssuesProvider.overrideWith(
            (ref, id) => Stream.value(issues[id]!)),
      ],
      child: const MaterialApp(home: ReadScreen()),
    ));
    // Arcs emit, then each arc's issues stream: let both land.
    for (var k = 0; k < 4; k++) {
      await t.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('Ultimate Endgame'), findsOneWidget);
    expect(find.text('1 OF 3 READ'), findsOneWidget);
    expect(find.text('Ultimates #19'), findsNothing, reason: 'read issues before the next one drop off');
    expect(find.text('Ultimates #20'), findsOneWidget);
    expect(find.text('Ultimates #21'), findsOneWidget);
    expect(find.text('Finished Order'), findsNothing, reason: 'a finished order hides');
    expect(find.text('Imported Event'), findsNothing, reason: 'only user arcs');
    await t.pumpWidget(const SizedBox());
  });
}
