import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:comic_reader_app/models/series.dart';
import 'package:comic_reader_app/providers/providers.dart';
import 'package:comic_reader_app/widgets/series_detail_header.dart';

void main() {
  // Regression: the Download / Mark Read / Favorite buttons laid an icon and a
  // label side by side in a third of the row. In the iPad split-view panel
  // (and on a phone) a third is narrower than "Mark Read", so the labels ran
  // into each other.
  for (final width in [330.0, 420.0, 900.0]) {
    testWidgets('secondary actions fit at width $width', (t) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await t.binding.setSurfaceSize(Size(width, 1600));
      addTearDown(() => t.binding.setSurfaceSize(null));

      await t.pumpWidget(ProviderScope(
        overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SeriesDetailHeader(
                detail: const SeriesDetail(
                  id: 's1',
                  name: 'Absolute Batman 2025 Annual (2025)',
                  folderPath: '/x',
                  issueCount: 1,
                  readCount: 0,
                  coverUrl: '',
                  issues: [],
                ),
                coverImageUrl: null,
                isPanel: true,
                accent: Colors.blue,
                seriesId: 's1',
                resumeButtonContent: const Text('Resume #1'),
                progress: 0,
              ),
            ),
          ),
        ),
      ));
      await t.pump();

      expect(t.takeException(), isNull,
          reason: 'no overflow at width $width');
      for (final label in ['Download', 'Mark Read', 'Favorite']) {
        expect(find.text(label), findsOneWidget);
      }
      // Labels must not overlap each other.
      final download = t.getRect(find.text('Download'));
      final markRead = t.getRect(find.text('Mark Read'));
      final favorite = t.getRect(find.text('Favorite'));
      expect(download.right, lessThanOrEqualTo(markRead.left));
      expect(markRead.right, lessThanOrEqualTo(favorite.left));
    });
  }
}
