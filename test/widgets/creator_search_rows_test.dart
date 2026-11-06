import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/providers/providers.dart';

import 'package:comic_reader_app/models/creator_profile.dart';
import 'package:comic_reader_app/providers/creator_provider.dart';
import 'package:comic_reader_app/screens/creator_detail_screen.dart';
import 'package:comic_reader_app/widgets/creator_search_rows.dart';

class _PushSpy extends NavigatorObserver {
  Route<dynamic>? pushed;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed = route;
  }
}

// Tom King has more series than Stephen King — the "king" query should
// surface him first.
const _kingCreators = [
  CreatorSummary(
      id: 1,
      name: 'Tom King',
      roles: ['writer'],
      seriesIds: ['s1', 's2', 's3', 's4', 's5', 's6', 's7']),
  CreatorSummary(id: 2, name: 'Stephen King', roles: ['writer'], seriesIds: ['s8']),
];

Future<void> _pump(
  WidgetTester t, {
  required String query,
  required List<CreatorSummary> Function(Ref ref) createCreators,
  NavigatorObserver? observer,
}) async {
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        gutterFeaturesProvider.overrideWithValue(true),
        creatorsProvider.overrideWith(createCreators),
      ],
      child: MaterialApp(
        navigatorObservers: observer != null ? [observer] : const [],
        home: Scaffold(body: CreatorSearchRows(query: query)),
      ),
    ),
  );
  await t.pump();
  await t.pump(const Duration(milliseconds: 50));
}

void main() {
  testWidgets('"king" shows Tom King before Stephen King', (t) async {
    await _pump(t, query: 'king', createCreators: (ref) => _kingCreators);

    expect(find.text('Tom King'), findsOneWidget);
    expect(find.text('Stephen King'), findsOneWidget);
    final tomY = t.getTopLeft(find.text('Tom King')).dy;
    final stephenY = t.getTopLeft(find.text('Stephen King')).dy;
    expect(tomY, lessThan(stephenY),
        reason: 'higher series count (7 vs 1) should sort first');
  });

  testWidgets('empty query shows nothing', (t) async {
    await _pump(t, query: '', createCreators: (ref) => _kingCreators);

    expect(find.text('CREATORS'), findsNothing);
    expect(find.text('Tom King'), findsNothing);
  });

  testWidgets('provider error shows nothing, no error text', (t) async {
    await _pump(
      t,
      query: 'king',
      createCreators: (ref) => throw Exception('offline'),
    );

    expect(find.text('CREATORS'), findsNothing);
    expect(find.text('Tom King'), findsNothing);
    expect(find.textContaining('offline'), findsNothing);
    expect(find.textContaining('Error'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('tapping a row pushes the creator detail screen', (t) async {
    final spy = _PushSpy();
    await _pump(t,
        query: 'king', createCreators: (ref) => _kingCreators, observer: spy);

    await t.tap(find.text('Tom King'));
    // Deliberately not pumped further: openCreator's push for a known id
    // (>0) is synchronous, same as creator_detail_panel's openCreator tests.
    final route = spy.pushed as MaterialPageRoute;
    final pushedWidget = route.builder(t.element(find.byType(MaterialApp)));
    expect(pushedWidget, isA<CreatorDetailScreen>());
    expect((pushedWidget as CreatorDetailScreen).creatorId, 1);
    expect(pushedWidget.name, 'Tom King');
  });
}
