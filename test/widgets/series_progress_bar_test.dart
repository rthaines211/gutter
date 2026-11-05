import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/config/app_theme.dart';
import 'package:comic_reader_app/config/scheme.dart';
import 'package:comic_reader_app/widgets/series_progress_bar.dart';

const _accent = Color(0xFF0A84FF);

Future<void> _pump(WidgetTester t, Widget child) async {
  await t.pumpWidget(MaterialApp(
    theme: AppTheme.themeData(Scheme.oledBlack),
    home: Scaffold(body: child),
  ));
}

/// Reads the fill color of segment [index] by digging into the Container
/// keyed ValueKey('progress-segment-$index').
Color _segmentColor(WidgetTester t, int index) {
  final finder = find.byKey(ValueKey('progress-segment-$index'));
  final container = t.widget<Container>(finder);
  final decoration = container.decoration as BoxDecoration;
  return decoration.color!;
}

int _segmentCount(WidgetTester t) {
  return t.widgetList(find.byWidgetPredicate((w) {
    final key = w.key;
    return key is ValueKey && key.value.toString().startsWith('progress-segment-');
  })).length;
}

void main() {
  group('SeriesProgressBar', () {
    testWidgets('fewer issues than 24 renders one segment per issue', (t) async {
      await _pump(t, SeriesProgressBar(total: 3, read: 1, accent: _accent));
      expect(_segmentCount(t), 3);
    });

    testWidgets('more than 24 issues groups into exactly 24 segments', (t) async {
      await _pump(t, SeriesProgressBar(total: 72, read: 30, accent: _accent));
      expect(_segmentCount(t), 24);
    });

    testWidgets('exactly 24 issues renders 24 segments, one per issue', (t) async {
      await _pump(t, SeriesProgressBar(total: 24, read: 10, accent: _accent));
      expect(_segmentCount(t), 24);
    });

    testWidgets('zero read shows no green or accent segments', (t) async {
      await _pump(t, SeriesProgressBar(total: 5, read: 0, accent: _accent));
      for (var i = 0; i < 5; i++) {
        expect(_segmentColor(t, i), isNot(AppTheme.green));
        expect(_segmentColor(t, i), isNot(_accent));
      }
    });

    testWidgets('all read shows all segments green with no accent', (t) async {
      await _pump(t, SeriesProgressBar(total: 5, read: 5, accent: _accent));
      for (var i = 0; i < 5; i++) {
        expect(_segmentColor(t, i), AppTheme.green);
      }
    });

    testWidgets('zero-issue series renders no segments and does not throw', (t) async {
      await _pump(t, SeriesProgressBar(total: 0, read: 0, accent: _accent));
      expect(_segmentCount(t), 0);
      expect(t.takeException(), isNull);
    });

    testWidgets('one-to-one mapping: read segments are green, unread are not', (t) async {
      await _pump(t, SeriesProgressBar(total: 5, read: 2, currentIndex: 2, accent: _accent));
      expect(_segmentColor(t, 0), AppTheme.green);
      expect(_segmentColor(t, 1), AppTheme.green);
      expect(_segmentColor(t, 2), _accent); // current issue highlight
      expect(_segmentColor(t, 3), isNot(AppTheme.green));
      expect(_segmentColor(t, 3), isNot(_accent));
      expect(_segmentColor(t, 4), isNot(AppTheme.green));
    });

    testWidgets('current-issue highlight lands in the correct GROUP when grouped', (t) async {
      // 72 issues -> 24 segments, 3 issues per segment. read=30 means issues
      // 0..29 are read (10 full groups: 0-2,3-5,...,27-29), current issue is
      // index 30, which falls in group 10 (issues 30-32).
      await _pump(t, SeriesProgressBar(total: 72, read: 30, currentIndex: 30, accent: _accent));
      for (var i = 0; i < 10; i++) {
        expect(_segmentColor(t, i), AppTheme.green, reason: 'group $i should be fully read');
      }
      expect(_segmentColor(t, 10), _accent, reason: 'group 10 contains the current issue');
      for (var i = 11; i < 24; i++) {
        expect(_segmentColor(t, i), isNot(AppTheme.green), reason: 'group $i should not be read');
        expect(_segmentColor(t, i), isNot(_accent), reason: 'group $i should not be current');
      }
    });

    testWidgets('a partially-read group (round-down rule) is NOT rendered green', (t) async {
      // 4 issues, 24 max segments -> 4 segments, 1 issue each (no grouping),
      // so use a case that actually groups: 26 issues -> 24 segments where
      // most groups have 1 issue but 2 groups have 2 issues (spread evenly).
      // read=1 with total=26: only issue 0 is read. Whichever group issue 0
      // belongs to, since it may share the group with issue 1 (unread), that
      // group must NOT be green under the round-down (fully-read) rule.
      await _pump(t, SeriesProgressBar(total: 26, read: 1, accent: _accent));
      // group 0 covers issue index 0 (and possibly 1) -- since read=1 only
      // covers issue 0, group 0 is only fully read if it is a 1-issue group.
      // With 26 issues over 24 segments, boundaries via ceil(26*i/24) mean
      // group 0 = issues [0,1) (size 1) since ceil(26*1/24)=2... verify via
      // the fully-read rule directly: segment is green iff read >= its end
      // boundary. Group 0's end boundary is ceil(26*1/24) = 2, so read=1 < 2
      // means group 0 must NOT be green.
      expect(_segmentColor(t, 0), isNot(AppTheme.green));
    });

    testWidgets('a fully-read group IS rendered green even when it spans multiple issues', (t) async {
      // Same 26-into-24 grouping. Group 0 end boundary is 2 (issues 0-1).
      // read=2 means both issues in group 0 are read -> group 0 is green.
      await _pump(t, SeriesProgressBar(total: 26, read: 2, accent: _accent));
      expect(_segmentColor(t, 0), AppTheme.green);
    });

    testWidgets('currentIndex null renders no accent segment', (t) async {
      await _pump(t, SeriesProgressBar(total: 5, read: 5, accent: _accent));
      for (var i = 0; i < 5; i++) {
        expect(_segmentColor(t, i), isNot(_accent));
      }
    });
  });
}
