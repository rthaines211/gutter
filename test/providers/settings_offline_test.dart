import 'dart:convert';

import 'package:comic_reader_app/models/reader_settings.dart';
import 'package:comic_reader_app/providers/connectivity_provider.dart';
import 'package:comic_reader_app/providers/providers.dart';
import 'package:comic_reader_app/providers/settings_provider.dart';
import 'package:comic_reader_app/services/api_client.dart';
import 'package:comic_reader_app/services/app_logger.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeConnectivity extends ConnectivityNotifier {
  _FakeConnectivity(this._initial);
  final bool _initial;
  @override
  bool build() => _initial;
  @override
  Future<void> check() async {}
}

/// Reader settings must survive going offline: an RTL reader suddenly paging
/// LTR mid-issue is the failure these guard against.
void main() {
  late Map<String, dynamic> server;
  late List<String> puts;
  var serverUp = true;

  setUp(() async {
    await AppLogger.init(logDirFactory: () async => null);
    SharedPreferences.setMockInitialValues({});
    server = {'page_fit': 'fitHeight'};
    puts = [];
    serverUp = true;
  });

  tearDown(AppLogger.resetForTest);

  ProviderContainer make({required bool online}) {
    final c = ProviderContainer(overrides: [
      apiClientProvider.overrideWithValue(ApiClient(
        baseUrl: 'http://test',
        deviceId: 't',
        httpClient: MockClient((req) async {
          if (!serverUp) return http.Response('{"error":"down"}', 503);
          if (req.method == 'PUT') {
            puts.add(req.body);
            server = jsonDecode(req.body) as Map<String, dynamic>;
            return http.Response('{}', 200);
          }
          return http.Response(jsonEncode(server), 200);
        }),
      )),
      connectivityProvider.overrideWith(() => _FakeConnectivity(online)),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  test('offline launch uses the last settings seen online', () async {
    await make(online: true).read(settingsProvider.future);
    final s = await make(online: false).read(settingsProvider.future);
    expect(s.pageFit, 'fitHeight');
  });

  test('a change saved while the server is down is pushed next launch',
      () async {
    final c = make(online: true);
    final s = await c.read(settingsProvider.future);
    serverUp = false;
    await c.read(settingsProvider.notifier).save(s.copyWith(pageFit: 'fitWidth'));

    serverUp = true;
    final next = await make(online: true).read(settingsProvider.future);
    expect(next.pageFit, 'fitWidth');
    expect(server['page_fit'], 'fitWidth');
  });

  test('a connectivity flip does not reload settings', () async {
    final c = make(online: true);
    await c.read(settingsProvider.future);
    var reloads = 0;
    c.listen<AsyncValue<ReaderSettings>>(settingsProvider, (_, next) {
      if (next.isLoading) reloads++;
    });
    c.read(connectivityProvider.notifier).state = false;
    await Future<void>.delayed(Duration.zero);
    expect(reloads, 0);
  });
}
