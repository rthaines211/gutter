import 'package:flutter/material.dart';
import 'package:comic_reader_app/providers/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/models/series.dart';
import 'package:comic_reader_app/widgets/end_card.dart';

SeriesIssue _next() => SeriesIssue(
      id: 'next-id',
      name: 'Next Issue',
      number: '4',
      coverUrl: 'http://example.com/cover.jpg',
      status: 'unread',
      currentPage: null,
      totalPages: null,
    );

void main() {
  group('EndCard', () {
    testWidgets('offline: says the next issue is missing and offers the next one on the iPad',
        (tester) async {
      Widget card(SeriesIssue? next) => noImgAuth(MaterialApp(
            home: Scaffold(
              body: EndCard(
                currentIssueTitle: 'Batman 003',
                currentSeriesName: 'Batman (2012)',
                currentCoverUrl: 'http://example.com/current.jpg',
                readCount: 3,
                totalCount: 52,
                nextIssue: next,
                offlineNote: "#4 isn't on this iPad",
                onNext: () {},
                onBackToSeries: () {},
                onClose: () {},
              ),
            ),
          ));

      await tester.pumpWidget(card(_next()));
      expect(find.textContaining("#4 isn't on this iPad"), findsOneWidget);
      expect(find.byKey(const Key('endcard.next')), findsOneWidget);

      // Nothing later is downloaded: the note replaces "caught up".
      await tester.pumpWidget(card(null));
      expect(find.text("#4 isn't on this iPad"), findsOneWidget);
      expect(find.text("You're all caught up"), findsNothing);
    });

    testWidgets('renders identity, progress, and next-up when nextIssue is provided', (tester) async {
      var nextTaps = 0;
      var backTaps = 0;
      var closeTaps = 0;

      await tester.pumpWidget(
        noImgAuth(MaterialApp(
          home: Scaffold(
            body: EndCard(
              currentIssueTitle: 'Batman 003',
              currentSeriesName: 'Batman (2012)',
              currentCoverUrl: 'http://example.com/current.jpg',
              readCount: 3,
              totalCount: 52,
              nextIssue: _next(),
              onNext: () => nextTaps++,
              onBackToSeries: () => backTaps++,
              onClose: () => closeTaps++,
            ),
          ),
        )),
      );

      expect(find.text('Batman 003'), findsOneWidget);
      // Direction A (Spotlight) shows the series name twice by design: once
      // next to the finished issue, once as context under the next issue.
      expect(find.text('Batman (2012)'), findsNWidgets(2));
      expect(find.textContaining('3 / 52'), findsOneWidget);
      expect(find.textContaining('UP NEXT'), findsOneWidget);
      expect(find.text('Next Issue'), findsOneWidget);

      await tester.tap(find.byKey(const Key('endcard.next')));
      await tester.tap(find.byKey(const Key('endcard.backToSeries')));
      await tester.tap(find.byKey(const Key('endcard.close')));
      expect(nextTaps, 1);
      expect(backTaps, 1);
      expect(closeTaps, 1);
    });

    testWidgets('shows "caught up" badge and hides Next when nextIssue is null', (tester) async {
      await tester.pumpWidget(
        noImgAuth(MaterialApp(
          home: Scaffold(
            body: EndCard(
              currentIssueTitle: 'Final Issue',
              currentSeriesName: 'Some Series',
              currentCoverUrl: '',
              readCount: 12,
              totalCount: 12,
              nextIssue: null,
              onNext: () {},
              onBackToSeries: () {},
              onClose: () {},
            ),
          ),
        )),
      );

      expect(find.textContaining("caught up"), findsOneWidget);
      expect(find.byKey(const Key('endcard.next')), findsNothing);
      expect(find.byKey(const Key('endcard.backToSeries')), findsOneWidget);
      expect(find.byKey(const Key('endcard.close')), findsOneWidget);
    });
  });
}


/// Cover images ask for auth headers; these tests have no source.
Widget noImgAuth(Widget child) => ProviderScope(
      overrides: [imageHeadersProvider.overrideWithValue(const {})],
      child: child,
    );
