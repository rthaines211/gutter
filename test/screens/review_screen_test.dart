import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:comic_reader_app/providers/navigation_provider.dart';
import 'package:comic_reader_app/providers/providers.dart';
import 'package:comic_reader_app/services/push_service.dart';
import 'package:comic_reader_app/screens/review_screen.dart';
import 'package:comic_reader_app/services/api_client.dart';
import 'package:comic_reader_app/services/app_logger.dart';

Map<String, dynamic> _item(String id, {String state = 'no_match'}) => {
      'series_id': id,
      'name': id,
      'state': state,
      'local_cover_url': '',
      'guess_cover_url': '',
    };

void main() {
  setUpAll(() async {
    await AppLogger.init(logDirFactory: () async => null);
  });

  late int gets;
  late ProviderContainer container;

  Future<void> pump(
    WidgetTester t,
    Future<http.Response> Function() queue,
  ) async {
    gets = 0;
    container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(ApiClient(
          baseUrl: 'http://test',
          deviceId: 'd',
          httpClient: MockClient((r) {
            gets++;
            return queue();
          }),
        )),
      ],
    );
    addTearDown(container.dispose);
    await t.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: ReviewScreen()),
    ));
    await t.pump(const Duration(milliseconds: 50));
    await t.pump(const Duration(milliseconds: 50));
  }

  http.Response ok(List<Map<String, dynamic>> items) =>
      http.Response(jsonEncode({'count': items.length, 'items': items}), 200,
          headers: {'content-type': 'application/json'});

  testWidgets('shows all caught up when empty', (t) async {
    await pump(t, () async => ok([]));
    expect(find.text('All caught up'), findsOneWidget);
  });

  testWidgets('shows counter', (t) async {
    await pump(t, () async => ok([_item('a'), _item('b')]));
    expect(find.text('1 of 2'), findsOneWidget);
  });

  testWidgets('right disabled for no_match row', (t) async {
    await pump(t, () async => ok([_item('a')]));
    final b = t.widget<FilledButton>(find.widgetWithText(FilledButton, '✓ Right'));
    expect(b.onPressed, isNull);
  });

  testWidgets('collection row shows Collection and right enabled', (t) async {
    await pump(t, () async => ok([_item('a', state: 'collection')]));
    expect(find.text('Collection'), findsOneWidget);
    final b = t.widget<FilledButton>(find.widgetWithText(FilledButton, '✓ Right'));
    expect(b.onPressed, isNotNull);
  });

  testWidgets('shows retry on load error', (t) async {
    await pump(t, () async => http.Response('{"error":"boom"}', 500));
    expect(find.text('Retry'), findsOneWidget);
    final before = gets;
    await t.tap(find.text('Retry'));
    await t.pump(const Duration(milliseconds: 50));
    expect(gets, greaterThan(before));
  });

  testWidgets('selecting the Review tab refetches the queue', (t) async {
    await pump(t, () async => ok([_item('a')]));
    final before = gets;
    container.read(navigationProvider.notifier).go(NavDestination.review);
    await t.pump(const Duration(milliseconds: 50));
    expect(gets, greaterThan(before));
  });

  testWidgets('pull to refresh refetches', (t) async {
    await pump(t, () async => ok([]));
    final before = gets;
    await t.fling(find.text('All caught up'), const Offset(0, 300), 1000);
    await t.pump(const Duration(milliseconds: 500));
    await t.pump(const Duration(milliseconds: 500));
    expect(gets, greaterThan(before));
  });

  testWidgets('routePushTap review refetches the queue', (t) async {
    await pump(t, () async => ok([_item('a')]));
    final before = gets;
    routePushTap(container, 'review');
    await t.pump(const Duration(milliseconds: 50));
    await t.pump(const Duration(milliseconds: 50));
    expect(gets, greaterThan(before));
  });

  testWidgets('phone: deck buttons clear the floating tab bar', (t) async {
    t.view.physicalSize = const Size(400, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await pump(t, () async => ok([_item('a', state: 'collection')]));
    final bottom = t.getBottomLeft(find.widgetWithText(FilledButton, '✓ Right')).dy;
    expect(bottom, lessThanOrEqualTo(800 - 100));
  });

  testWidgets('shows folder name when guess differs', (t) async {
    final it = _item('Batman 2016')..['guess_volume_id'] = 'v1'..['guess_name'] = 'Batman';
    await pump(t, () async => ok([it]));
    expect(find.text('folder: Batman 2016'), findsOneWidget);
  });
}
