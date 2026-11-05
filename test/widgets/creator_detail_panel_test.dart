import 'dart:async';

import 'package:comic_reader_app/config/app_theme.dart';
import 'package:comic_reader_app/models/creator.dart';
import 'package:comic_reader_app/models/creator_profile.dart';
import 'package:comic_reader_app/models/series.dart';
import 'package:comic_reader_app/providers/creator_provider.dart';
import 'package:comic_reader_app/providers/mirror_provider.dart';
import 'package:comic_reader_app/providers/providers.dart';
import 'package:comic_reader_app/screens/creator_detail_screen.dart';
import 'package:comic_reader_app/screens/series_detail_screen.dart';
import 'package:comic_reader_app/services/api_client.dart';
import 'package:comic_reader_app/services/app_logger.dart';
import 'package:comic_reader_app/services/mirror/mirror_database.dart';
import 'package:comic_reader_app/widgets/creator_detail_panel.dart';
import 'package:comic_reader_app/widgets/volume_info_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _creatorId = 40724;
const _creatorName = 'Tom King';

BibliographyVolume _vol({
  required int volumeId,
  required String name,
  required int startYear,
  required List<String> roles,
  required OwnedState owned,
  String publisher = 'DC',
  int personIssues = 1,
  int totalIssues = 1,
  int ownedIssues = 0,
  String? seriesId,
}) =>
    BibliographyVolume(
      volumeId: volumeId,
      name: name,
      startYear: startYear,
      publisher: publisher,
      coverUrl: '',
      roles: roles,
      personIssues: personIssues,
      totalIssues: totalIssues,
      ownedIssues: ownedIssues,
      owned: owned,
      seriesId: seriesId,
    );

// Writer group has 1 volume (Wonder Woman, not owned); Art has 3 (owned,
// partial, owned) — so the default chip is Art, not Writer, and tapping
// Writer narrows the list down to just Wonder Woman.
final _bib = [
  _vol(
    volumeId: 301,
    name: 'Wonder Woman',
    startYear: 2024,
    roles: const ['writer'],
    owned: OwnedState.none,
    personIssues: 24,
    totalIssues: 24,
  ),
  _vol(
    volumeId: 302,
    name: 'Supergirl: Woman of Tomorrow',
    startYear: 2022,
    roles: const ['penciller'],
    owned: OwnedState.owned,
    totalIssues: 8,
    ownedIssues: 8,
    seriesId: 's-sotw',
  ),
  _vol(
    volumeId: 303,
    name: 'Strange Adventures',
    startYear: 2022,
    roles: const ['penciller'],
    owned: OwnedState.partial,
    totalIssues: 12,
    ownedIssues: 7,
    seriesId: 's-sa',
  ),
  _vol(
    volumeId: 304,
    name: 'Mister Miracle',
    startYear: 2017,
    roles: const ['inker'],
    owned: OwnedState.owned,
    totalIssues: 12,
    ownedIssues: 12,
    seriesId: 's-mm',
  ),
];

CreatorProfile _profile({
  List<BibliographyVolume>? bibliography,
  int volumesOwned = 3,
  int volumesTotal = 41,
  List<String> roles = const ['writer', 'penciller', 'inker'],
}) =>
    CreatorProfile(
      id: _creatorId,
      name: _creatorName,
      roles: roles,
      seriesIds: const ['s-sotw', 's-sa', 's-mm'],
      volumesOwned: volumesOwned,
      volumesTotal: volumesTotal,
      bibliography: bibliography,
      bibliographyPending: false,
    );

Series _series(
  String id, {
  String name = 'Series',
  int issueCount = 5,
  int readCount = 2,
  List<Creator> creators = const [],
  int? startYear,
}) {
  final at = DateTime.parse('2026-01-01T00:00:00Z');
  return Series(
    id: id,
    name: name,
    folderPath: '/comics/$id',
    issueCount: issueCount,
    readCount: readCount,
    coverUrl: '',
    creators: creators,
    createdAt: at,
    updatedAt: at,
    startYear: startYear,
  );
}

class _PushSpy extends NavigatorObserver {
  Route<dynamic>? pushed;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed = route;
  }
}

Future<void> _pump(
  WidgetTester t,
  Size size, {
  int creatorId = _creatorId,
  String name = _creatorName,
  required ({CreatorProfile profile, bool offline})? result,
  List<MirrorSeries> mirror = const [],
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
        creatorProfileProvider.overrideWith((ref, key) => result),
        mirrorLibraryProvider.overrideWith((ref) => Stream.value(mirror)),
      ],
      child: MaterialApp(
        navigatorObservers: observer != null ? [observer] : const [],
        home: Scaffold(
          body: CreatorDetailPanel(
            creatorId: creatorId,
            name: name,
            accent: AppTheme.accent,
          ),
        ),
      ),
    ),
  );
  await t.pump();
  await t.pump(const Duration(milliseconds: 50));
}

void main() {
  setUpAll(() async {
    await AppLogger.init(logDirFactory: () async => null);
  });

  for (final size in const [Size(1024, 1366), Size(390, 844)]) {
    testWidgets('header shows name, roles, stats and defaults to the largest group at $size',
        (t) async {
      await _pump(t, size,
          result: (profile: _profile(bibliography: _bib), offline: false));

      expect(find.text('Tom King'), findsOneWidget);
      expect(find.textContaining('Writer'), findsWidgets);
      expect(find.text('3'), findsOneWidget); // volumesOwned
      expect(find.text('41'), findsOneWidget); // volumesTotal
      expect(find.text('0'), findsOneWidget); // issues read (no mirror match)

      // Default chip is Art (3 volumes) not Writer (1 volume): Wonder Woman
      // (writer-only) is filtered out, Mister Miracle (art) is shown.
      expect(find.text('Mister Miracle'), findsOneWidget);
      expect(find.text('Wonder Woman'), findsNothing);

      // Years present in the default (Art) filter: 2022 and 2017, descending.
      final y2022 = t.getCenter(find.text('2022'));
      final y2017 = t.getCenter(find.text('2017'));
      expect(y2022.dy, lessThan(y2017.dy));
    });

    testWidgets('tapping Writer filters the list at $size', (t) async {
      await _pump(t, size,
          result: (profile: _profile(bibliography: _bib), offline: false));

      await t.tap(find.text('Writer'));
      await t.pump();

      expect(find.text('Wonder Woman'), findsOneWidget);
      expect(find.text('Mister Miracle'), findsNothing);
    });

    testWidgets('offline / null bibliography shows the fallback note and owned rows, no chips at $size',
        (t) async {
      final owned = _series(
        's-owned',
        name: 'Sheriff of Babylon',
        startYear: 2015,
        creators: const [Creator(id: _creatorId, name: _creatorName, role: 'writer')],
      );
      await _pump(
        t,
        size,
        result: (
          profile: _profile(bibliography: null, volumesOwned: 1, volumesTotal: 1),
          offline: true,
        ),
        mirror: [MirrorSeries(series: owned)],
      );

      expect(find.text('Full bibliography needs the server.'), findsOneWidget);
      expect(find.text('Sheriff of Babylon'), findsOneWidget);
      // Role chips are gone entirely in fallback mode (the roles line above
      // the stats joins all of them into one string, never standalone).
      expect(find.text('Writer'), findsNothing);
      expect(find.text('Art'), findsNothing);
    });
  }

  testWidgets('a null profile shows a simple empty state', (t) async {
    await _pump(t, const Size(1024, 1366), result: null, name: 'Nobody');
    expect(find.text('No works found for Nobody'), findsOneWidget);
    expect(find.textContaining('Failed'), findsNothing);
  });

  testWidgets('an owned row pushes SeriesDetailScreen', (t) async {
    final spy = _PushSpy();
    await _pump(
      t,
      const Size(1024, 1366),
      result: (profile: _profile(bibliography: _bib), offline: false),
      observer: spy,
    );

    await t.tap(find.text('Mister Miracle'));
    // Deliberately not pumped further: materializing the pushed
    // SeriesDetailScreen would resolve seriesDetailProvider against a real
    // mirror DB, which this test never sets up. The route's builder can be
    // called directly to inspect the widget without mounting it.
    final route = spy.pushed as MaterialPageRoute;
    final pushedWidget = route.builder(t.element(find.byType(MaterialApp)));
    expect(pushedWidget, isA<SeriesDetailScreen>());
    expect((pushedWidget as SeriesDetailScreen).seriesId, 's-mm');
  });

  testWidgets('a none row opens VolumeInfoSheet showing the description and no buttons',
      (t) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          creatorProfileProvider.overrideWith(
              (ref, key) => (profile: _profile(bibliography: _bib), offline: false)),
          mirrorLibraryProvider.overrideWith((ref) => Stream.value(const [])),
          volumeInfoProvider.overrideWith((ref, id) => VolumeInfo(
                volumeId: id,
                name: 'Wonder Woman',
                startYear: 2024,
                publisher: 'DC Comics',
                coverUrl: '',
                totalIssues: 24,
                description: 'Diana takes on the Sovereign.',
              )),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: CreatorDetailPanel(
              creatorId: _creatorId,
              name: _creatorName,
              accent: AppTheme.accent,
            ),
          ),
        ),
      ),
    );
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));

    // Switch to Writer to reveal the not-owned Wonder Woman row.
    await t.tap(find.text('Writer'));
    await t.pump();

    await t.tap(find.text('Wonder Woman'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));

    expect(find.byType(VolumeInfoSheet), findsOneWidget);
    expect(find.text('Diana takes on the Sovereign.'), findsOneWidget);
    expect(find.byType(ElevatedButton), findsNothing);
    expect(find.byType(TextButton), findsNothing);
  });

  testWidgets(
      'an owned row with a null seriesId opens VolumeInfoSheet instead of crashing',
      (t) async {
    // Stale/inconsistent server data: owned but with no seriesId. Force-
    // unwrapping seriesId here would crash; it must fall back to the sheet.
    final staleOwned = _vol(
      volumeId: 999,
      name: 'Stale Owned Volume',
      startYear: 2019,
      roles: const ['writer'],
      owned: OwnedState.owned,
      totalIssues: 6,
      ownedIssues: 6,
      seriesId: null,
    );
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          creatorProfileProvider.overrideWith((ref, key) =>
              (profile: _profile(bibliography: [staleOwned]), offline: false)),
          mirrorLibraryProvider.overrideWith((ref) => Stream.value(const [])),
          volumeInfoProvider.overrideWith((ref, id) => VolumeInfo(
                volumeId: id,
                name: 'Stale Owned Volume',
                startYear: 2019,
                publisher: 'DC',
                coverUrl: '',
                totalIssues: 6,
                description: '',
              )),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: CreatorDetailPanel(
              creatorId: _creatorId,
              name: _creatorName,
              accent: AppTheme.accent,
            ),
          ),
        ),
      ),
    );
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));

    await t.tap(find.text('Stale Owned Volume'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));

    expect(find.byType(VolumeInfoSheet), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('300 volumes render lazily without building every row', (t) async {
    // Years run opposite to the index so index order matches render order
    // (years sort descending): index 0 is the top row, index 299 the last.
    final many = [
      for (var i = 0; i < 300; i++)
        _vol(
          volumeId: 1000 + i,
          name: 'Volume $i',
          startYear: 2100 - i,
          roles: const ['writer'],
          owned: OwnedState.owned,
          totalIssues: 1,
          ownedIssues: 1,
          seriesId: 's$i',
        ),
    ];
    await _pump(
      t,
      const Size(1024, 1366),
      result: (profile: _profile(bibliography: many), offline: false),
    );

    // A volume far down the (very long) list isn't built before scrolling.
    expect(find.text('Volume 290'), findsNothing);
  });

  group('openCreator', () {
    ApiClient clientReturning(int status, String body) => ApiClient(
          baseUrl: 'http://test',
          deviceId: 'd',
          httpClient: MockClient((req) async => http.Response(body, status)),
        );

    /// Pumps a bare widget tree that captures a [BuildContext]/[WidgetRef]
    /// pair for calling [openCreator] directly from the test body, without
    /// going through a tap. [observer] records the pushed route.
    Future<({BuildContext context, WidgetRef ref})> pumpHarness(
      WidgetTester t, {
      required ApiClient apiClient,
      NavigatorObserver? observer,
    }) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      late BuildContext capturedContext;
      late WidgetRef capturedRef;
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPrefsProvider.overrideWithValue(prefs),
            apiClientProvider.overrideWithValue(apiClient),
            mirrorLibraryProvider.overrideWith((ref) => Stream.value(const <MirrorSeries>[])),
          ],
          child: MaterialApp(
            navigatorObservers: observer != null ? [observer] : const [],
            home: Scaffold(
              body: Consumer(builder: (context, ref, _) {
                capturedContext = context;
                capturedRef = ref;
                return const SizedBox();
              }),
            ),
          ),
        ),
      );
      await t.pump();
      return (context: capturedContext, ref: capturedRef);
    }

    testWidgets('id>0: the future does not complete until the route pops', (t) async {
      final spy = _PushSpy();
      final h = await pumpHarness(t, apiClient: clientReturning(200, '[]'), observer: spy);

      var completed = false;
      unawaited(openCreator(h.context, h.ref, id: 40724, name: _creatorName)
          .then((_) => completed = true));
      await t.pump();

      expect(spy.pushed, isNotNull);
      expect(completed, isFalse);

      t.state<NavigatorState>(find.byType(Navigator)).pop();
      await t.pump();

      expect(completed, isTrue);
    });

    testWidgets('id 0 with 1 lookup match pushes with that match\'s id', (t) async {
      final spy = _PushSpy();
      final h = await pumpHarness(
        t,
        apiClient: clientReturning(200, '[{"id": 40724, "name": "Tom King", "volumes": 3}]'),
        observer: spy,
      );

      unawaited(openCreator(h.context, h.ref, id: 0, name: _creatorName));
      await t.pump();

      final route = spy.pushed as MaterialPageRoute;
      final pushed = route.builder(h.context);
      expect(pushed, isA<CreatorDetailScreen>());
      expect((pushed as CreatorDetailScreen).creatorId, 40724);
    });

    testWidgets('id 0 with 0 matches pushes with id 0', (t) async {
      final spy = _PushSpy();
      final h = await pumpHarness(t, apiClient: clientReturning(200, '[]'), observer: spy);

      unawaited(openCreator(h.context, h.ref, id: 0, name: _creatorName));
      await t.pump();

      final route = spy.pushed as MaterialPageRoute;
      final pushed = route.builder(h.context);
      expect(pushed, isA<CreatorDetailScreen>());
      expect((pushed as CreatorDetailScreen).creatorId, 0);
    });

    testWidgets('id 0 with the lookup throwing pushes with id 0', (t) async {
      final spy = _PushSpy();
      final h = await pumpHarness(
        t,
        apiClient: clientReturning(500, '{"error": "boom"}'),
        observer: spy,
      );

      unawaited(openCreator(h.context, h.ref, id: 0, name: _creatorName));
      await t.pump();

      final route = spy.pushed as MaterialPageRoute;
      final pushed = route.builder(h.context);
      expect(pushed, isA<CreatorDetailScreen>());
      expect((pushed as CreatorDetailScreen).creatorId, 0);
    });
  });
}
