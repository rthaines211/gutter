import 'package:comic_reader_app/models/creator.dart';
import 'package:comic_reader_app/models/creator_profile.dart';
import 'package:comic_reader_app/models/series.dart';
import 'package:comic_reader_app/providers/creator_provider.dart';
import 'package:comic_reader_app/providers/mirror_provider.dart';
import 'package:comic_reader_app/providers/providers.dart';
import 'package:comic_reader_app/screens/creator_detail_screen.dart';
import 'package:comic_reader_app/screens/creators_screen.dart';
import 'package:comic_reader_app/services/mirror/mirror_database.dart';
import 'package:comic_reader_app/widgets/creator_detail_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _at = DateTime.parse('2026-01-01T00:00:00Z');

Series _series(
  String id, {
  required String name,
  int issueCount = 5,
  int readCount = 0,
  List<Creator> creators = const [],
}) =>
    Series(
      id: id,
      name: name,
      folderPath: '/comics/$id',
      issueCount: issueCount,
      readCount: readCount,
      coverUrl: '',
      creators: creators,
      createdAt: _at,
      updatedAt: _at,
    );

class _PushSpy extends NavigatorObserver {
  Route<dynamic>? pushed;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed = route;
  }
}

// Tom King (writer, spotlit — reading "Strange Adventures"), Mitch Gerads
// (penciller, 1 owned series), Ed Brubaker (writer, 2 owned series), Alice
// Artist (artist, 1 owned series).
const _tomKing = CreatorSummary(
    id: 1, name: 'Tom King', roles: ['writer'], seriesIds: ['s1', 's2']);
const _mitchGerads = CreatorSummary(
    id: 2, name: 'Mitch Gerads', roles: ['penciller'], seriesIds: ['s2']);
const _edBrubaker = CreatorSummary(
    id: 3, name: 'Ed Brubaker', roles: ['writer'], seriesIds: ['s3', 's4']);
const _aliceArtist = CreatorSummary(
    id: 4, name: 'Alice Artist', roles: ['artist'], seriesIds: ['s5']);

const _creators = [_tomKing, _mitchGerads, _edBrubaker, _aliceArtist];

List<MirrorSeries> _readingMirror() => [
      MirrorSeries(
        series: _series('s1',
            name: 'Strange Adventures',
            issueCount: 5,
            readCount: 2,
            creators: const [Creator(id: 1, name: 'Tom King', role: 'writer')]),
        lastReadAt: DateTime.now(),
        nextUnreadIssueId: 'c3',
      ),
      MirrorSeries(
        series: _series('s2',
            name: 'Batman',
            issueCount: 3,
            readCount: 3,
            creators: const [
              Creator(id: 1, name: 'Tom King', role: 'writer'),
              Creator(id: 2, name: 'Mitch Gerads', role: 'penciller'),
            ]),
      ),
      MirrorSeries(
        series: _series('s3',
            name: 'Criminal',
            issueCount: 4,
            readCount: 0,
            creators: const [Creator(id: 3, name: 'Ed Brubaker', role: 'writer')]),
      ),
      MirrorSeries(
        series: _series('s4',
            name: 'Fatale',
            issueCount: 4,
            readCount: 0,
            creators: const [Creator(id: 3, name: 'Ed Brubaker', role: 'writer')]),
      ),
      MirrorSeries(
        series: _series('s5',
            name: 'Something Else',
            issueCount: 2,
            readCount: 0,
            creators: const [Creator(id: 4, name: 'Alice Artist', role: 'artist')]),
      ),
    ];

/// Same roster, nothing read anywhere — no reading history.
List<MirrorSeries> _noHistoryMirror() => _readingMirror()
    .map((m) => MirrorSeries(
          series: _series(m.series.id,
              name: m.series.name,
              issueCount: m.series.issueCount,
              readCount: 0,
              creators: m.series.creators),
        ))
    .toList();

Future<void> _pump(
  WidgetTester t,
  Size size, {
  List<CreatorSummary> creators = _creators,
  List<MirrorSeries>? mirror,
  NavigatorObserver? observer,
}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        coversDirProvider.overrideWithValue(null),
        creatorsProvider.overrideWith((ref) => creators),
        mirrorLibraryProvider
            .overrideWith((ref) => Stream.value(mirror ?? _readingMirror())),
        creatorProfileProvider.overrideWith((ref, key) => (
              profile: CreatorProfile(
                id: key.id,
                name: key.name,
                roles: const [],
                seriesIds: const [],
                volumesOwned: 0,
                volumesTotal: 0,
                bibliography: null,
                bibliographyPending: false,
              ),
              offline: true,
            )),
      ],
      child: MaterialApp(
        navigatorObservers: observer != null ? [observer] : const [],
        home: const CreatorsScreen(),
      ),
    ),
  );
  await t.pump();
  await t.pump(const Duration(milliseconds: 50));
}

void main() {
  const tablet = Size(1366, 1024); // landscape tablet: panelFraction 0.40
  const phone = Size(390, 844);

  testWidgets('spotlight shows reading label, name and next-by-them',
      (t) async {
    await _pump(t, tablet);

    expect(find.text("YOU'RE READING"), findsOneWidget);
    expect(find.text('Tom King'), findsOneWidget);
    expect(find.text('Next by them: Strange Adventures'), findsOneWidget);
    expect(find.text('Open Tom King'), findsOneWidget);
  });

  testWidgets('the grid excludes the spotlit creator', (t) async {
    await _pump(t, tablet);

    // 'Tom King' appears exactly once (the spotlight header) — not again as
    // a grid card.
    expect(find.text('Tom King'), findsOneWidget);
    expect(find.text('Mitch Gerads'), findsOneWidget);
    expect(find.text('Ed Brubaker'), findsOneWidget);
    expect(find.text('Alice Artist'), findsOneWidget);
  });

  testWidgets('filter text narrows the grid', (t) async {
    await _pump(t, tablet);

    await t.enterText(find.byType(TextField), 'Mitch');
    await t.pump();

    expect(find.text('Mitch Gerads'), findsOneWidget);
    expect(find.text('Ed Brubaker'), findsNothing);
    expect(find.text('Alice Artist'), findsNothing);
  });

  testWidgets('Writers chip hides art-only creators', (t) async {
    await _pump(t, tablet);

    await t.tap(find.text('Writers'));
    await t.pump();

    expect(find.text('Ed Brubaker'), findsOneWidget);
    expect(find.text('Mitch Gerads'), findsNothing);
    expect(find.text('Alice Artist'), findsNothing);
  });

  testWidgets('sorting A-Z reorders the grid', (t) async {
    await _pump(t, tablet);

    // Default "Most series": Ed Brubaker (2 series) sorts before Mitch
    // Gerads and Alice Artist (1 series each, tied alphabetically).
    final edDefaultX = t.getCenter(find.text('Ed Brubaker')).dx;
    final mitchDefaultX = t.getCenter(find.text('Mitch Gerads')).dx;
    expect(edDefaultX, lessThan(mitchDefaultX));

    await t.tap(find.text('Most series'));
    await t.pump();

    // A-Z: Alice Artist, Ed Brubaker, Mitch Gerads.
    final aliceX = t.getCenter(find.text('Alice Artist')).dx;
    final edX = t.getCenter(find.text('Ed Brubaker')).dx;
    final mitchX = t.getCenter(find.text('Mitch Gerads')).dx;
    expect(aliceX, lessThan(edX));
    expect(edX, lessThan(mitchX));
  });

  testWidgets('no reading history hides the spotlight', (t) async {
    await _pump(t, tablet, mirror: _noHistoryMirror());

    expect(find.text("YOU'RE READING"), findsNothing);
    expect(find.text('MOST READ'), findsNothing);
    // Nobody excluded from the grid since there's no spotlight.
    expect(find.text('Tom King'), findsOneWidget);
  });

  testWidgets('on iPad, tapping a card shows CreatorDetailPanel beside the grid',
      (t) async {
    await _pump(t, tablet);

    await t.tap(find.text('Ed Brubaker'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));

    expect(find.byType(CreatorDetailPanel), findsOneWidget);
    // Landscape tablet: panel is 40% of the screen width.
    final panelWidth = t.getSize(find.byType(CreatorDetailPanel)).width;
    expect(panelWidth, closeTo(tablet.width * 0.40, 1));
    // The grid is still showing beside it.
    expect(find.text('Mitch Gerads'), findsOneWidget);

    // onClose clears the selection.
    await t.tap(find.byIcon(Icons.close));
    await t.pump();
    expect(find.byType(CreatorDetailPanel), findsNothing);
  });

  testWidgets(
      'on iPad, tapping "Open <name>" on the spotlight selects it into the panel instead of pushing',
      (t) async {
    final spy = _PushSpy();
    await _pump(t, tablet, observer: spy);
    // MaterialApp's own initial route push already set this; capture it so
    // the later assertion can tell "no new push" from "never pushed".
    final initialRoute = spy.pushed;

    await t.tap(find.text('Open Tom King'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));

    expect(find.byType(CreatorDetailPanel), findsOneWidget);
    final panelWidth = t.getSize(find.byType(CreatorDetailPanel)).width;
    expect(panelWidth, closeTo(tablet.width * 0.40, 1));
    expect(spy.pushed, same(initialRoute),
        reason: 'tapping Open must select into the panel, not push a route');
  });

  testWidgets('on phone, tapping a card pushes CreatorDetailScreen', (t) async {
    final spy = _PushSpy();
    await _pump(t, phone, observer: spy);

    await t.tap(find.text('Ed Brubaker'));
    // Deliberately not pumped further — materializing the pushed screen
    // would resolve creator/mirror providers again; inspect the route's
    // builder directly instead.
    final route = spy.pushed as MaterialPageRoute;
    final pushedWidget = route.builder(t.element(find.byType(MaterialApp)));
    expect(pushedWidget, isA<CreatorDetailScreen>());
    expect((pushedWidget as CreatorDetailScreen).creatorId, 3);
    expect(pushedWidget.name, 'Ed Brubaker');
  });
}
