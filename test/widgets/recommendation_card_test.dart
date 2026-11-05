import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:comic_reader_app/models/recommendation.dart';
import 'package:comic_reader_app/providers/providers.dart';
import 'package:comic_reader_app/providers/recommendation_provider.dart';
import 'package:comic_reader_app/widgets/recommendation_card.dart';

class _FixedNotifier extends RecommendationNotifier {
  _FixedNotifier(this._value);
  final AsyncValue<Recommendation?> _value;

  @override
  Future<Recommendation?> build() async {
    switch (_value) {
      case AsyncData<Recommendation?>(:final value):
        return value;
      case AsyncError<Recommendation?>(:final error):
        throw error;
      case _:
        // AsyncLoading — never resolve
        await Completer<Recommendation?>().future;
        return null;
    }
  }
}

Future<Widget> _harness(
    Widget child, AsyncValue<Recommendation?> value) async {
  final prefs = await SharedPreferences.getInstance();
  return ProviderScope(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      recommendationProvider.overrideWith(() => _FixedNotifier(value)),
    ],
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('renders SizedBox.shrink when value is null', (tester) async {
    await tester.pumpWidget(await _harness(const RecommendationCard(),
        const AsyncData<Recommendation?>(null)));
    await tester.pump();
    expect(find.textContaining('What should'), findsNothing);
    expect(find.text('Open'), findsNothing);
    expect(find.text('Re-roll'), findsNothing);
  });

  testWidgets('renders loaded in-library state with Open + Re-roll',
      (tester) async {
    const rec = Recommendation(
      seriesId: 's1', title: 'Saga, Vol 4', creator: 'BKV',
      reasoning: 'You binge BKV.', isInLibrary: true,
    );
    await tester.pumpWidget(await _harness(const RecommendationCard(),
        const AsyncData<Recommendation?>(rec)));
    await tester.pump();
    expect(find.text('Saga, Vol 4'), findsOneWidget);
    expect(find.text('BKV'), findsOneWidget);
    expect(find.text('You binge BKV.'), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Re-roll'), findsOneWidget);
  });

  testWidgets('renders unowned state without Open button', (tester) async {
    const rec = Recommendation(
      seriesId: null, title: 'Trees', creator: 'Ellis',
      reasoning: 'vibes', isInLibrary: false,
    );
    await tester.pumpWidget(await _harness(const RecommendationCard(),
        const AsyncData<Recommendation?>(rec)));
    await tester.pump();
    expect(find.text('Trees'), findsOneWidget);
    expect(find.text('Open'), findsNothing);
    expect(find.text('Re-roll'), findsOneWidget);
  });

  testWidgets('renders shimmer on loading', (tester) async {
    await tester.pumpWidget(await _harness(const RecommendationCard(),
        const AsyncLoading<Recommendation?>()));
    // don't pump — still in loading state
    expect(find.byKey(const Key('rec-card-shimmer')), findsOneWidget);
  });

  testWidgets('renders error chip with Try again', (tester) async {
    await tester.pumpWidget(await _harness(const RecommendationCard(),
        AsyncError<Recommendation?>(Exception('boom'), StackTrace.empty)));
    await tester.pumpAndSettle();
    expect(find.text('Try again'), findsOneWidget);
  });
}
