import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:comic_reader_app/config/comic_style.dart';
import 'package:comic_reader_app/models/series.dart';
import 'package:comic_reader_app/providers/providers.dart';
import 'package:comic_reader_app/widgets/panel_frame.dart';
import 'package:comic_reader_app/widgets/series_grid_tile.dart';

final _series = Series(
  id: '1',
  name: 'Test Series',
  folderPath: '/test',
  issueCount: 10,
  readCount: 0, // isUnread
  coverUrl: '',
  createdAt: DateTime.now(), // isRecentlyAdded -> exercises the NEW badge/CaptionBox
  updatedAt: DateTime.now(),
);

Future<void> _pumpTile(WidgetTester tester, ComicStyle style) async {
  SharedPreferences.setMockInitialValues({'comic_style': style.name});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 200,
            height: 300,
            child: SeriesGridTile(
              series: _series,
              serverUrl: 'http://localhost',
              onTap: () {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  for (final style in ComicStyle.values) {
    testWidgets('SeriesGridTile renders under $style with no exception',
        (tester) async {
      await _pumpTile(tester, style);

      expect(tester.takeException(), isNull);
      expect(find.text('NEW'), findsOneWidget);
      // One badge only: there is no separate ADDED badge.
      expect(find.text('ADDED'), findsNothing);
    });
  }

  testWidgets('off style still yields a blurred (not hard) shadow on PanelFrame',
      (tester) async {
    await _pumpTile(tester, ComicStyle.off);

    final container = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(PanelFrame),
            matching: find.byType(Container),
          )
          .first,
    );
    final decoration = container.decoration as BoxDecoration;
    expect(decoration.boxShadow, isNotNull);
    expect(decoration.boxShadow!.isNotEmpty, isTrue);
    expect(decoration.boxShadow!.any((s) => s.blurRadius > 0), isTrue);
  });
}
