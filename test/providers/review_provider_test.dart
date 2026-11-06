import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:comic_reader_app/providers/providers.dart';
import 'package:comic_reader_app/providers/review_provider.dart';
import 'package:comic_reader_app/services/api_client.dart';
import 'package:comic_reader_app/services/app_logger.dart';

Map<String, dynamic> _item(String id) => {'series_id': id, 'name': id};

http.Response _queue(List<String> ids) => http.Response(
      jsonEncode({'count': ids.length, 'items': ids.map(_item).toList()}),
      200,
      headers: {'content-type': 'application/json'},
    );

void main() {
  setUpAll(() async {
    await AppLogger.init(logDirFactory: () async => null);
  });

  late List<http.Request> requests;

  ProviderContainer make(Future<http.Response> Function(http.Request) h) {
    requests = [];
    final c = ProviderContainer(overrides: [
        gutterFeaturesProvider.overrideWithValue(true),
      apiClientProvider.overrideWithValue(ApiClient(
        baseUrl: 'http://test',
        deviceId: 'test-device',
        httpClient: MockClient((r) {
          requests.add(r);
          return h(r);
        }),
      )),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  List<String> ids(ProviderContainer c) =>
      c.read(reviewQueueProvider).value!.items.map((i) => i.seriesId).toList();

  test('confirm removes current and keeps cursor', () async {
    final c = make((r) async =>
        r.method == 'GET' ? _queue(['a', 'b', 'c']) : http.Response('', 204));
    await c.read(reviewQueueProvider.future);
    c.read(reviewQueueProvider.notifier).skip();
    await c.read(reviewQueueProvider.notifier).confirm();
    expect(ids(c), ['a', 'c']);
    expect(c.read(reviewQueueProvider).value!.cursor, 1);
    expect(requests.where((r) => r.method == 'GET').length, 1);
  });

  test('skip wraps', () async {
    final c = make((r) async => _queue(['a', 'b']));
    await c.read(reviewQueueProvider.future);
    final n = c.read(reviewQueueProvider.notifier);
    n.skip();
    expect(c.read(reviewQueueProvider).value!.cursor, 1);
    n.skip();
    expect(c.read(reviewQueueProvider).value!.cursor, 0);
  });

  test('confirm ignores re-entry while busy', () async {
    final gate = Completer<void>();
    final c = make((r) async {
      if (r.method == 'GET') return _queue(['a', 'b']);
      await gate.future;
      return http.Response('', 204);
    });
    await c.read(reviewQueueProvider.future);
    final n = c.read(reviewQueueProvider.notifier);
    final first = n.confirm();
    final second = n.confirm();
    gate.complete();
    await Future.wait([first, second]);
    expect(requests.where((r) => r.method == 'POST').length, 1);
    expect(ids(c), ['b']);
  });

  test('action failure reloads queue and rethrows', () async {
    var gets = 0;
    final c = make((r) async {
      if (r.method == 'GET') return _queue(gets++ == 0 ? ['a', 'b'] : ['z']);
      return http.Response(jsonEncode({'error': 'conflict'}), 409,
          headers: {'content-type': 'application/json'});
    });
    await c.read(reviewQueueProvider.future);
    await expectLater(c.read(reviewQueueProvider.notifier).confirm(),
        throwsA(isA<ApiException>()));
    expect(ids(c), ['z']);
    expect(c.read(reviewQueueProvider).value!.busy, false);
  });

  test('empty queue current is null', () async {
    final c = make((r) async => _queue([]));
    final s = await c.read(reviewQueueProvider.future);
    expect(s.current, isNull);
    expect(s.cursor, 0);
    expect(c.read(reviewCountProvider), 0);
  });

  test('reload during an in-flight action is ignored; action removes right item', () async {
    final gate = Completer<void>();
    final c = make((r) async {
      if (r.method == 'GET') return _queue(['a', 'b']);
      await gate.future;
      return http.Response('', 204);
    });
    await c.read(reviewQueueProvider.future);
    final n = c.read(reviewQueueProvider.notifier);
    final act = n.confirm();
    await n.reload();
    expect(requests.where((r) => r.method == 'GET').length, 1);
    expect(c.read(reviewQueueProvider).value!.busy, true);
    expect(ids(c), ['a', 'b']);
    gate.complete();
    await act;
    expect(ids(c), ['b']);
    expect(c.read(reviewQueueProvider).value!.busy, false);
  });
}
