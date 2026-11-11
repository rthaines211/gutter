import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:comic_reader_app/models/stats_summary.dart';
import 'package:comic_reader_app/providers/providers.dart';
import 'package:comic_reader_app/providers/stats_provider.dart';
import 'package:comic_reader_app/screens/stats_screen.dart';
import 'package:comic_reader_app/widgets/stats_share_card.dart';

StatsSummary _summary({int allTimePages = 4321}) => StatsSummary(
      allTime: PeriodStats(pagesRead: allTimePages, issuesFinished: 87, seriesCompleted: 5, timeReadS: 0),
      thisWeek: const PeriodStats(pagesRead: 212, issuesFinished: 3, seriesCompleted: 0, timeReadS: 0),
      thisMonth: const PeriodStats(pagesRead: 0, issuesFinished: 0, seriesCompleted: 0, timeReadS: 0),
      pagesPerDay: const [],
      topGenres: const [],
      topPublishers: const [],
      // On the summary, but never on the card.
      topSeries: const [
        SeriesPages(seriesId: 's', name: 'Secret Series', pages: 9, timeReadS: 0, coverUrl: ''),
      ],
      topWriters: const [NameCount(name: 'Secret Writer', count: 1)],
      avgSessionS: 0,
      completionRate: const CompletionRate(started: 0, completed: 0, ratePercent: 0),
      streak: const StreakStats(current: 6, longest: 9),
      hourHistogram: const [],
    );

class _NoHistory extends StatsHistoryNotifier {
  @override
  StatsHistoryState build() => const StatsHistoryState();
}

Future<void> _pumpScreen(WidgetTester t, StatsSummary summary) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await t.pumpWidget(ProviderScope(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      statsSummaryProvider.overrideWith((ref) => summary),
      statsHistoryProvider.overrideWith(_NoHistory.new),
    ],
    child: const MaterialApp(home: StatsScreen()),
  ));
  await t.pump();
}

void main() {
  testWidgets('card shows the numbers, the wordmark and the site, and no titles', (t) async {
    await t.pumpWidget(MaterialApp(home: Center(child: StatsShareCard(summary: _summary()))));
    expect(t.getSize(find.byType(StatsShareCard)), StatsShareCard.size);
    expect(find.text('212'), findsOneWidget); // pages this week
    expect(find.text('6'), findsOneWidget); // streak
    expect(find.text('87'), findsOneWidget); // issues finished
    expect(find.text('4321'), findsOneWidget); // pages all time
    expect(find.text('Gutter'), findsOneWidget);
    expect(find.text('getgutter.app'), findsOneWidget);
    expect(find.textContaining('Secret'), findsNothing);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('card renders off-screen to a 1080x1350 PNG', (t) async {
    late BuildContext context;
    await t.pumpWidget(MaterialApp(home: Builder(builder: (c) {
      context = c;
      return const SizedBox();
    })));
    late Future<Uint8List> bytes;
    final image = await t.runAsync(() async {
      bytes = renderStatsCardPng(context, _summary(), Colors.blue);
      await t.pump(); // the frame that paints the card
      return (await (await ui.instantiateImageCodec(await bytes)).getNextFrame()).image;
    });
    expect((image!.width, image.height), (1080, 1350));
    image.dispose();
    await t.pump();
    expect(find.byType(StatsShareCard), findsNothing); // taken off the overlay again
  });

  testWidgets('Stats header has Share when there are stats', (t) async {
    await _pumpScreen(t, _summary());
    expect(find.byTooltip('Share your stats'), findsOneWidget);
  });

  testWidgets('Stats header has no Share with empty stats', (t) async {
    await _pumpScreen(t, _summary(allTimePages: 0));
    expect(find.text('Stats'), findsOneWidget);
    expect(find.byTooltip('Share your stats'), findsNothing);
  });
}
