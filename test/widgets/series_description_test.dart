import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:comic_reader_app/providers/providers.dart';
import 'package:comic_reader_app/widgets/series_enrichment_section.dart';
import 'package:comic_reader_app/models/creator.dart';

Future<void> _pump(WidgetTester tester, Widget child, {double width = 400}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(ProviderScope(
    overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
    child: MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SizedBox(width: width, child: child),
        ),
      ),
    ),
  ));
}

/// Creators start collapsed to one summary line; open the card grid.
Future<void> _expandCreators(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('creators-summary')));
  await tester.pump();
}

void main() {
  testWidgets('renders description clamped to 3 lines and expands on tap',
      (tester) async {
    final longText = List.filled(60, 'word').join(' ');
    await _pump(tester, SeriesEnrichmentSection(
      description: longText,
      creators: const [],
    ));
    expect(find.textContaining('word'), findsOneWidget);
    final text = tester.widget<Text>(find.textContaining('word'));
    expect(text.maxLines, 3);
    expect(find.text('MORE'), findsOneWidget);
    await tester.tap(find.text('MORE'));
    await tester.pump();
    expect(find.text('LESS'), findsOneWidget);
    final expandedText = tester.widget<Text>(find.textContaining('word'));
    expect(expandedText.maxLines, isNull);
  });

  testWidgets('renders creators grouped by role in a 2-column grid at phone width',
      (tester) async {
    await _pump(tester, const SeriesEnrichmentSection(
      description: null,
      creators: [
        Creator(name: 'Scott Snyder', role: 'writer'),
        Creator(name: 'Greg Capullo', role: 'penciler, cover'),
        Creator(name: 'James Tynion IV', role: 'writer'),
      ],
    ), width: 400);
    await _expandCreators(tester);
    expect(find.text('WRITER'), findsOneWidget);
    expect(find.text('Scott Snyder, James Tynion IV'), findsOneWidget);
    expect(find.text('PENCILER'), findsOneWidget);
    expect(find.text('Greg Capullo'), findsOneWidget);

    final grid = tester.widget<GridView>(find.byType(GridView));
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisCount, 2);
  });

  testWidgets('creator grid switches to 4 columns when wide', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await _pump(tester, const SeriesEnrichmentSection(
      description: null,
      creators: [
        Creator(name: 'Scott Snyder', role: 'writer'),
        Creator(name: 'Greg Capullo', role: 'penciler'),
      ],
    ), width: 900);
    await _expandCreators(tester);
    final grid = tester.widget<GridView>(find.byType(GridView));
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisCount, 4);
  });

  testWidgets('renders nothing when empty', (tester) async {
    await _pump(tester, const SeriesEnrichmentSection(
      description: null,
      creators: [],
    ));
    expect(find.byType(SizedBox), findsWidgets); // collapses to shrink
    expect(find.text('MORE'), findsNothing);
  });
}
