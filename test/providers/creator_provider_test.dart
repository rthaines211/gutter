import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:comic_reader_app/models/creator.dart';
import 'package:comic_reader_app/models/creator_profile.dart';
import 'package:comic_reader_app/models/series.dart';
import 'package:comic_reader_app/providers/connectivity_provider.dart';
import 'package:comic_reader_app/providers/creator_provider.dart';
import 'package:comic_reader_app/providers/mirror_provider.dart';
import 'package:comic_reader_app/providers/providers.dart';
import 'package:comic_reader_app/services/api_client.dart';
import 'package:comic_reader_app/services/app_logger.dart';
import 'package:comic_reader_app/services/mirror/mirror_database.dart';

/// Test double: bypasses the real notifier's timers/lifecycle setup and lets
/// the test drive the bool directly. Same pattern as
/// test/widgets/connectivity_overlay_test.dart's FakeConnectivity.
class _FakeConnectivity extends ConnectivityNotifier {
  _FakeConnectivity(this._initial);
  final bool _initial;

  @override
  bool build() => _initial;

  @override
  Future<void> check() async {}

  void emit(bool online) => state = online;
}

Series _series(String id, {List<Creator> creators = const []}) {
  final at = DateTime.parse('2026-01-01T00:00:00Z');
  return Series(
    id: id,
    name: 'Series $id',
    folderPath: '/comics/$id',
    issueCount: 5,
    readCount: 0,
    coverUrl: '',
    creators: creators,
    createdAt: at,
    updatedAt: at,
  );
}

void main() {
  setUpAll(() async {
    await AppLogger.init(logDirFactory: () async => null);
  });

  late List<http.Request> requests;

  ProviderContainer make({
    required Future<http.Response> Function(http.Request) handler,
    List<MirrorSeries> mirror = const [],
  }) {
    requests = [];
    final container = ProviderContainer(overrides: [
        gutterFeaturesProvider.overrideWithValue(true),
      apiClientProvider.overrideWithValue(ApiClient(
        baseUrl: 'http://test',
        deviceId: 'test-device',
        httpClient: MockClient((req) {
          requests.add(req);
          return handler(req);
        }),
      )),
      mirrorLibraryProvider.overrideWith((ref) => Stream.value(mirror)),
      // creatorsProvider watches connectivityProvider; the real notifier's
      // timers/AppLifecycleListener need a full widget binding this bare
      // ProviderContainer doesn't have. Keep it inert for tests that don't
      // care about connectivity transitions.
      connectivityProvider.overrideWith(() => _FakeConnectivity(true)),
    ]);
    // A bare ProviderContainer (no widget pump driving the event loop) never
    // resolves mirrorLibraryProvider.future unless something keeps it alive
    // with a real listener; reading .future once isn't enough.
    container.listen(mirrorLibraryProvider, (prev, next) {});
    addTearDown(container.dispose);
    return container;
  }

  Future<({CreatorProfile profile, bool offline})?> readProfile(
          ProviderContainer container, CreatorKey key) =>
      container.read(creatorProfileProvider(key).future);

  test('id 0 makes no HTTP call and returns the owned-only profile by name', () async {
    final tomKing = const Creator(id: 0, name: 'Tom King', role: 'writer');
    final container = make(
      handler: (_) async => http.Response('should not be called', 500),
      mirror: [MirrorSeries(series: _series('s1', creators: [tomKing]))],
    );
    final result = await readProfile(container, (id: 0, name: 'Tom King'));
    expect(requests, isEmpty);
    expect(result, isNotNull);
    expect(result!.offline, false);
    expect(result.profile.bibliography, isNull);
    expect(result.profile.seriesIds, ['s1']);
  });

  test('id 0 with no owned matches returns null', () async {
    final container = make(handler: (_) async => http.Response('', 500));
    final result = await readProfile(container, (id: 0, name: 'Nobody'));
    expect(requests, isEmpty);
    expect(result, isNull);
  });

  test('SocketException falls back to the owned-only profile with offline true', () async {
    final tomKing = const Creator(id: 40724, name: 'Tom King', role: 'writer');
    final container = make(
      handler: (_) async => throw const SocketException('no route'),
      mirror: [MirrorSeries(series: _series('s1', creators: [tomKing]))],
    );
    final result =
        await readProfile(container, (id: 40724, name: 'Tom King'));
    expect(result, isNotNull);
    expect(result!.offline, true);
    expect(result.profile.bibliography, isNull);
  });

  test('a malformed 200 response falls back to the owned-only profile with offline true',
      () async {
    final tomKing = const Creator(id: 40724, name: 'Tom King', role: 'writer');
    final container = make(
      handler: (_) async => http.Response('not json', 200),
      mirror: [MirrorSeries(series: _series('s1', creators: [tomKing]))],
    );
    final result =
        await readProfile(container, (id: 40724, name: 'Tom King'));
    expect(result, isNotNull);
    expect(result!.offline, true);
    expect(result.profile.bibliography, isNull);
  });

  test('a 404 falls back to the owned-only profile with offline false', () async {
    final tomKing = const Creator(id: 40724, name: 'Tom King', role: 'writer');
    final container = make(
      handler: (_) async => http.Response(jsonEncode({'error': 'not found'}), 404),
      mirror: [MirrorSeries(series: _series('s1', creators: [tomKing]))],
    );
    final result =
        await readProfile(container, (id: 40724, name: 'Tom King'));
    expect(result, isNotNull);
    expect(result!.offline, false);
    expect(result.profile.bibliography, isNull);
  });

  test('a server profile with a null bibliography is returned as-is, offline false', () async {
    final container = make(
      handler: (_) async => http.Response(
        jsonEncode({
          'id': 40724,
          'name': 'Tom King',
          'roles': ['writer'],
          'seriesIds': ['s1'],
          'volumesOwned': 1,
          'volumesTotal': 5,
          'bibliography': null,
          'bibliographyPending': true,
        }),
        200,
      ),
    );
    final result =
        await readProfile(container, (id: 40724, name: 'Tom King'));
    expect(result, isNotNull);
    expect(result!.offline, false);
    expect(result.profile.bibliography, isNull);
    expect(result.profile.bibliographyPending, true);
  });

  test(
      'creatorsProvider: a failing request yields AsyncError promptly, with no retry',
      () async {
    final container = make(handler: (_) async => http.Response('fail', 500));
    await expectLater(container.read(creatorsProvider.future), throwsA(anything));
    expect(requests, hasLength(1));
  });

  test(
      'volumeInfoProvider: a failing request yields AsyncError promptly, with no retry',
      () async {
    final container = make(handler: (_) async => http.Response('fail', 500));
    await expectLater(container.read(volumeInfoProvider(9).future), throwsA(anything));
    expect(requests, hasLength(1));
  });

  test('creatorsProvider refetches when connectivity flips from offline to online',
      () async {
    final fake = _FakeConnectivity(false);
    var calls = 0;
    final container = ProviderContainer(overrides: [
        gutterFeaturesProvider.overrideWithValue(true),
      connectivityProvider.overrideWith(() => fake),
      apiClientProvider.overrideWithValue(ApiClient(
        baseUrl: 'http://test',
        deviceId: 'test-device',
        httpClient: MockClient((req) async {
          calls++;
          return http.Response(jsonEncode(<Object>[]), 200);
        }),
      )),
    ]);
    addTearDown(container.dispose);
    // Keep the autoDispose provider alive across the connectivity flip, the
    // same way CreatorsScreen staying mounted in the IndexedStack does.
    container.listen(creatorsProvider, (prev, next) {});

    await container.read(creatorsProvider.future);
    expect(calls, 1);

    fake.emit(true);
    await container.read(creatorsProvider.future);
    expect(calls, 2);
  });
}
