import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:comic_reader_app/models/comic_info.dart';
import 'package:comic_reader_app/models/creator.dart';
import 'package:comic_reader_app/providers/creator_provider.dart';
import 'package:comic_reader_app/providers/providers.dart';
import 'package:comic_reader_app/screens/creator_detail_screen.dart';
import 'package:comic_reader_app/services/api_client.dart';
import 'package:comic_reader_app/services/app_logger.dart';
import 'package:comic_reader_app/services/mirror/library_view.dart';
import 'package:comic_reader_app/widgets/creator_detail_panel.dart' show openCreator;
import 'package:comic_reader_app/widgets/issue_credits_sheet.dart';
import 'package:comic_reader_app/widgets/shimmer_box.dart';

class _PushSpy extends NavigatorObserver {
  Route<dynamic>? pushed;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed = route;
  }
}

ApiClient _clientReturning(int status, String body) => ApiClient(
      baseUrl: 'http://test',
      deviceId: 'd',
      httpClient: MockClient((req) async => http.Response(body, status)),
    );

/// Opens the sheet the way the reader does: a button push shows a real
/// [showModalBottomSheet] route so the sheet's own `Navigator.pop()` has
/// something to pop.
Future<void> _openSheet(
  WidgetTester t, {
  required ApiClient apiClient,
  ComicInfo? info,
  String title = 'fallback.cbz',
  NavigatorObserver? observer,
  void Function(int id, String name)? onOpen,
}) async {
  await t.pumpWidget(ProviderScope(
    overrides: [apiClientProvider.overrideWithValue(apiClient)],
    child: MaterialApp(
      navigatorObservers: observer != null ? [observer] : const [],
      home: Scaffold(
        body: Consumer(
          builder: (context, ref, _) => ElevatedButton(
            onPressed: () => showModalBottomSheet(
              context: context,
              builder: (_) => IssueCreditsSheet(
                comicId: 'c1',
                info: info,
                title: title,
                onOpen: onOpen ??
                    (id, name) => openCreator(context, ref, id: id, name: name),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await t.tap(find.text('open'));
  await t.pump(); // showModalBottomSheet pushed
  await t.pump(const Duration(milliseconds: 300)); // entrance animation
  await t.pump(); // issueCreditsProvider resolves
  await t.pump(const Duration(milliseconds: 50));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await AppLogger.init(logDirFactory: () async => null);
  });

  group('creditsFromComicInfo', () {
    test('splits comma lists and parses a trailing [id]', () {
      final result = creditsFromComicInfo(const ComicInfo(
        title: '',
        pageCount: 0,
        writer: 'Tom King, Scott Snyder',
        penciller: 'Mark Waid [40724]',
      ));
      expect(
        result.map((c) => (c.id, c.name, c.role)).toList(),
        [
          (0, 'Tom King', 'writer'),
          (0, 'Scott Snyder', 'writer'),
          (40724, 'Mark Waid', 'penciller'),
        ],
      );
    });

    test('null info returns an empty list', () {
      expect(creditsFromComicInfo(null), isEmpty);
    });

    test('skips empty/whitespace names', () {
      final result = creditsFromComicInfo(const ComicInfo(
        title: '',
        pageCount: 0,
        writer: 'Tom King, , Scott Snyder,   ',
      ));
      expect(result.map((c) => c.name).toList(), ['Tom King', 'Scott Snyder']);
    });
  });

  group('IssueCreditsSheet', () {
    testWidgets('title is "series #number" when ComicInfo has both', (t) async {
      await _openSheet(
        t,
        apiClient: _clientReturning(200, jsonEncode(<Object>[])),
        info: const ComicInfo(
            title: 'x', pageCount: 1, series: 'Batman', number: '80'),
      );
      expect(find.text('Batman #80'), findsOneWidget);
      expect(find.text('Credits'), findsOneWidget);
    });

    testWidgets('title falls back to the passed-in title otherwise', (t) async {
      await _openSheet(
        t,
        apiClient: _clientReturning(200, jsonEncode(<Object>[])),
        title: 'Some Comic.cbz',
      );
      expect(find.text('Some Comic.cbz'), findsOneWidget);
    });

    testWidgets('shows shimmer rows while loading', (t) async {
      // Override the provider directly with a Completer that's never
      // completed — going through the real ApiClient/http.timeout() would
      // leave a raw Timer pending at teardown.
      final neverResolves = Completer<List<Creator>?>();
      addTearDown(() => neverResolves.complete(const []));
      await t.pumpWidget(ProviderScope(
        overrides: [
          issueCreditsProvider('c1').overrideWith((ref) => neverResolves.future),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: IssueCreditsSheet(
              comicId: 'c1',
              info: null,
              title: 'x',
              onOpen: (_, _) {},
            ),
          ),
        ),
      ));
      await t.pump();
      expect(find.byType(ShimmerBox), findsWidgets);
    });

    testWidgets('without onOpen no name is tappable', (t) async {
      await t.pumpWidget(ProviderScope(
        overrides: [
          issueCreditsProvider('c1').overrideWith((ref) async =>
              const [Creator(name: 'Tom King', role: 'writer')]),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: IssueCreditsSheet(comicId: 'c1', info: null, title: 'x'),
          ),
        ),
      ));
      await t.pump();
      expect(find.text('Tom King'), findsOneWidget);
      expect(
          t.widget<InkWell>(find.ancestor(
              of: find.text('Tom King'), matching: find.byType(InkWell))).onTap,
          isNull);
    });

    testWidgets('server credits list each role; writer is tappable, letterer is not',
        (t) async {
      await _openSheet(
        t,
        apiClient: _clientReturning(
          200,
          jsonEncode([
            {'id': 40724, 'name': 'Tom King', 'role': 'writer'},
            {'id': 55, 'name': 'Todd Klein', 'role': 'letterer'},
          ]),
        ),
      );

      expect(find.text('Writer'), findsOneWidget);
      expect(find.text('Tom King'), findsOneWidget);
      expect(find.text('Letterer'), findsOneWidget);
      expect(find.text('Todd Klein'), findsOneWidget);
      // One chevron for the tappable writer row; none for the letterer row.
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    });

    testWidgets('a comma-joined role renders each part capitalised and joined with " · "',
        (t) async {
      await _openSheet(
        t,
        apiClient: _clientReturning(
          200,
          jsonEncode([
            {'id': 1, 'name': 'Jim Lee', 'role': 'writer, cover'},
          ]),
        ),
      );

      expect(find.text('Writer · Cover'), findsOneWidget);
    });

    testWidgets('tapping the letterer does nothing', (t) async {
      final spy = _PushSpy();
      await _openSheet(
        t,
        observer: spy,
        apiClient: _clientReturning(
          200,
          jsonEncode([
            {'id': 55, 'name': 'Todd Klein', 'role': 'letterer'},
          ]),
        ),
      );
      final before = spy.pushed;

      await t.tap(find.text('Todd Klein'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));

      expect(spy.pushed, same(before));
      expect(find.text('Credits'), findsOneWidget, reason: 'sheet stays open');
      expect(t.takeException(), isNull);
    });

    testWidgets(
        'tapping a writer with a known id pops the sheet and opens the creator page',
        (t) async {
      final spy = _PushSpy();
      await _openSheet(
        t,
        observer: spy,
        apiClient: _clientReturning(
          200,
          jsonEncode([
            {'id': 40724, 'name': 'Tom King', 'role': 'writer'},
          ]),
        ),
      );

      // Deliberately not pumped: materializing the pushed screen would build
      // CreatorDetailPanel against real providers. The push is synchronous
      // (known id, no lookup), so spy.pushed is already set — same pattern
      // as series_enrichment_section_test.dart.
      await t.tap(find.text('Tom King'));

      final route = spy.pushed as MaterialPageRoute;
      final pushedWidget = route.builder(t.element(find.byType(MaterialApp)));
      expect(pushedWidget, isA<CreatorDetailScreen>());
      expect((pushedWidget as CreatorDetailScreen).creatorId, 40724);
      expect(pushedWidget.name, 'Tom King');
    });

    testWidgets('fetchIssueCredits returning null falls back to ComicInfo',
        (t) async {
      await _openSheet(
        t,
        apiClient: _clientReturning(404, jsonEncode({'error': 'no cv id'})),
        info: const ComicInfo(title: '', pageCount: 0, writer: 'Tom King'),
      );

      expect(find.text('Writer'), findsOneWidget);
      expect(find.text('Tom King'), findsOneWidget);
    });

    testWidgets('fetchIssueCredits throwing falls back to ComicInfo', (t) async {
      final client = ApiClient(
        baseUrl: 'http://test',
        deviceId: 'd',
        httpClient: MockClient((req) async => http.Response('boom', 500)),
      );
      await _openSheet(
        t,
        apiClient: client,
        info: const ComicInfo(title: '', pageCount: 0, writer: 'Tom King'),
      );

      expect(find.text('Writer'), findsOneWidget);
      expect(find.text('Tom King'), findsOneWidget);
    });

    testWidgets('empty server list falls back to ComicInfo', (t) async {
      await _openSheet(
        t,
        apiClient: _clientReturning(200, jsonEncode(<Object>[])),
        info: const ComicInfo(title: '', pageCount: 0, penciller: 'Mark Waid'),
      );

      expect(find.text('Penciller'), findsOneWidget);
      expect(find.text('Mark Waid'), findsOneWidget);
    });

    testWidgets('no server credits and no ComicInfo shows the empty message',
        (t) async {
      await _openSheet(
        t,
        apiClient: _clientReturning(200, jsonEncode(<Object>[])),
      );

      expect(find.text('No credits for this issue.'), findsOneWidget);
    });
  });
}
