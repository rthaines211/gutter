import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:comic_reader_app/models/creator.dart';
import 'package:comic_reader_app/providers/mirror_provider.dart';
import 'package:comic_reader_app/providers/providers.dart';
import 'package:comic_reader_app/screens/creator_detail_screen.dart';
import 'package:comic_reader_app/services/api_client.dart';
import 'package:comic_reader_app/services/app_logger.dart';
import 'package:comic_reader_app/widgets/series_enrichment_section.dart';

class _PushSpy extends NavigatorObserver {
  Route<dynamic>? pushed;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed = route;
  }
}

Future<void> _pump(WidgetTester t, Size size,
    {List<Creator> creators = const [],
    bool expand = true,
    NavigatorObserver? observer,
    ApiClient? apiClient}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await t.binding.setSurfaceSize(size);
  addTearDown(() => t.binding.setSurfaceSize(null));
  await t.pumpWidget(ProviderScope(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      if (apiClient != null) apiClientProvider.overrideWithValue(apiClient),
      // Any id-0 lookup that resolves with zero matches pushes
      // CreatorDetailScreen, which (via CreatorDetailPanel) reads the
      // mirror for its owned-only fallback. Stub it so a stray pump after
      // that push doesn't spin up a real drift database.
      if (apiClient != null)
        mirrorLibraryProvider.overrideWith((ref) => Stream.value(const [])),
    ],
    child: MaterialApp(
      navigatorObservers: observer != null ? [observer] : const [],
      home: Scaffold(
        body: SingleChildScrollView(
          child: SeriesEnrichmentSection(
            description: null,
            creators: creators,
          ),
        ),
      ),
    ),
  ));
  await t.pump();
  // Creators start collapsed to one line; the card-grid tests open them.
  // (Loops re-pump the same tree, which keeps it expanded.)
  final summary = find.byKey(const ValueKey('creators-summary'));
  if (expand && summary.evaluate().isNotEmpty) {
    await t.tap(summary);
    await t.pump();
  }
}

const _creators = [
  Creator(name: 'Alex Sinclair, David Baron', role: 'colorist'),
  Creator(name: 'Geoff Johns, Grant Morrison, Greg Rucka', role: 'writer'),
  Creator(name: 'J.G. Jones', role: 'cover'),
  Creator(name: 'Jack Jadson, Jimmy Palmiotti', role: 'inker'),
];

/// Real credits from a weekly title — the case that exposed both bugs.
const _longCreators = [
  Creator(
      name: 'Chris Batista, Eddy Barrows, Joe Bennett, Keith Giffen, '
          'Pat Olliffe, Darick Robertson',
      role: 'penciler'),
  Creator(
      name: 'Jack Jadson, Jimmy Palmiotti, Marlo Alquiza, Rodney Ramos, '
          'Wayne Faucher',
      role: 'inker'),
  Creator(name: 'X', role: 'cover'),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await AppLogger.init(logDirFactory: () async => null);
  });

  testWidgets('creator cards hug their content instead of squaring off',
      (t) async {
    // Regression: the grid used childAspectRatio 1.5, so each card was as tall
    // as it was wide — ~390pt on an iPad — leaving one line of text stranded
    // above a huge empty box. The height must track the content, not the
    // column width.
    await _pump(t, const Size(1194, 900), creators: _creators);

    final rows = (_creators.length / 4).ceil();
    final gridHeight = t.getRect(find.byType(GridView)).height;
    // rows * cardHeight + (rows - 1) * spacing
    expect(gridHeight, lessThan(rows * 120.0),
        reason: 'cards should be ~95pt tall, not scaled to column width');
    expect(t.takeException(), isNull);
  });

  testWidgets('cards do not overflow at either column count', (t) async {
    // 4 columns above the 820pt breakpoint, 2 below. A card that fits one and
    // overflows the other is the failure mode a fixed height can still hit.
    for (final size in [const Size(1194, 900), const Size(700, 900)]) {
      await _pump(t, size, creators: _creators);
      expect(t.takeException(), isNull,
          reason: 'no overflow at width ${size.width}');
    }
  });

  testWidgets('long credit lists wrap to two lines without overflowing',
      (t) async {
    // A role group often credits half a dozen people. One line hid most of
    // them behind an ellipsis; two lines plus a Flexible name means a tight
    // fit degrades to fewer visible names rather than a layout error.
    for (final size in [
      const Size(1194, 1600),
      const Size(700, 1600),
      const Size(500, 1600),
    ]) {
      await _pump(t, size, creators: _longCreators);
      expect(t.takeException(), isNull,
          reason: 'no overflow at width ${size.width}');

      // Not enough on its own: `Flexible` lets the name shrink to one line
      // rather than overflow, so an under-tall card passes an
      // exception-only check while silently truncating again. Assert the
      // name actually gets its two lines.
      final nameFinder = find.textContaining('Chris Batista');
      final painted = t.renderObject<RenderParagraph>(nameFinder);
      expect(painted.size.height, greaterThan(30),
          reason: 'the name should render two lines at width '
              '${size.width}, not be squeezed to one');
    }
  });

  testWidgets('creators start collapsed to one line, tap expands',
      (t) async {
    await _pump(t, const Size(500, 900), creators: _creators, expand: false);

    // Collapsed: no card grid, one summary row led by the writers.
    expect(find.byType(GridView), findsNothing);
    final summary = find.byKey(const ValueKey('creators-summary'));
    expect(summary, findsOneWidget);
    expect(find.descendant(of: summary, matching: find.text('WRITER')),
        findsOneWidget);
    expect(
        find.descendant(
            of: summary, matching: find.textContaining('Geoff Johns')),
        findsOneWidget);
    expect(find.descendant(of: summary, matching: find.text('+3 more')),
        findsOneWidget);
    expect(t.getRect(summary).height, lessThan(40),
        reason: 'collapsed creators should be a single line');

    await t.tap(summary);
    await t.pump();
    expect(find.byType(GridView), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('single role group has no +more', (t) async {
    await _pump(t, const Size(500, 900),
        creators: const [Creator(name: 'J.G. Jones', role: 'cover')],
        expand: false);
    final summary = find.byKey(const ValueKey('creators-summary'));
    expect(find.descendant(of: summary, matching: find.text('COVER')),
        findsOneWidget);
    expect(find.textContaining('more'), findsNothing);
  });

  testWidgets('renders nothing without description or creators', (t) async {
    await _pump(t, const Size(1194, 900));
    expect(find.byType(GridView), findsNothing);
  });

  group('tappable credits', () {
    testWidgets('tapping a writer with a known id pushes CreatorDetailScreen',
        (t) async {
      final spy = _PushSpy();
      await _pump(t, const Size(1194, 900), observer: spy, creators: const [
        Creator(id: 40724, name: 'Tom King', role: 'writer'),
      ]);

      await t.tap(find.text('Tom King'));
      // Deliberately not pumped further: materializing the pushed screen
      // would build CreatorDetailPanel against real providers. The push is
      // synchronous (known id, no lookup), so spy.pushed is already set.
      final route = spy.pushed as MaterialPageRoute;
      final pushedWidget = route.builder(t.element(find.byType(MaterialApp)));
      expect(pushedWidget, isA<CreatorDetailScreen>());
      expect((pushedWidget as CreatorDetailScreen).creatorId, 40724);
      expect(pushedWidget.name, 'Tom King');
    });

    testWidgets('tapping a letterer does nothing', (t) async {
      final spy = _PushSpy();
      await _pump(t, const Size(1194, 900), observer: spy, creators: const [
        Creator(id: 55, name: 'Todd Klein', role: 'letterer'),
      ]);
      // MaterialApp pushes its own initial route on launch, so spy.pushed
      // is already non-null here — capture it to tell "no new push" apart
      // from "never pushed" (same pattern as creators_screen_test.dart).
      final initialRoute = spy.pushed;

      await t.tap(find.text('Todd Klein'));
      await t.pump();

      expect(spy.pushed, same(initialRoute));
      expect(t.takeException(), isNull);
    });

    testWidgets('tapping an id-0 creator looks up the name via the api',
        (t) async {
      final requests = <http.Request>[];
      final client = ApiClient(
        baseUrl: 'http://test',
        deviceId: 'd',
        httpClient: MockClient((req) async {
          requests.add(req);
          return http.Response(jsonEncode(<Object>[]), 200);
        }),
      );
      await _pump(t, const Size(1194, 900), apiClient: client, creators: const [
        Creator(name: 'Tom King', role: 'writer'),
      ]);

      await t.tap(find.text('Tom King'));
      await t.pump();

      expect(requests.single.url.path, '/creators/lookup');
      expect(requests.single.url.queryParameters['name'], 'Tom King');
    });

    testWidgets('two lookup matches show a picker listing both', (t) async {
      final client = ApiClient(
        baseUrl: 'http://test',
        deviceId: 'd',
        httpClient: MockClient((req) async => http.Response(
            jsonEncode([
              {'id': 1, 'name': 'Tom King', 'volumes': 3},
              {'id': 2, 'name': 'Tom King (artist)', 'volumes': 1},
            ]),
            200)),
      );
      await _pump(t, const Size(1194, 900), apiClient: client, creators: const [
        Creator(name: 'Tom King', role: 'writer'),
      ]);

      await t.tap(find.text('Tom King'));
      await t.pumpAndSettle();

      expect(find.text('Tom King'), findsWidgets);
      expect(find.text('Tom King (artist)'), findsOneWidget);
    });

    testWidgets('zero lookup matches pushes CreatorDetailScreen with id 0',
        (t) async {
      final spy = _PushSpy();
      final client = ApiClient(
        baseUrl: 'http://test',
        deviceId: 'd',
        httpClient:
            MockClient((req) async => http.Response(jsonEncode(<Object>[]), 200)),
      );
      await _pump(t, const Size(1194, 900),
          observer: spy, apiClient: client, creators: const [
        Creator(name: 'Tom King', role: 'writer'),
      ]);

      await t.tap(find.text('Tom King'));
      await t.pump();

      final route = spy.pushed as MaterialPageRoute;
      final pushedWidget = route.builder(t.element(find.byType(MaterialApp)));
      expect(pushedWidget, isA<CreatorDetailScreen>());
      expect((pushedWidget as CreatorDetailScreen).creatorId, 0);
    });
  });
}
