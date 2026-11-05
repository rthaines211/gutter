import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:comic_reader_app/providers/providers.dart';
import 'package:comic_reader_app/providers/rename_templates_provider.dart';
import 'package:comic_reader_app/services/api_client.dart';
import 'package:comic_reader_app/services/app_logger.dart';

void main() {
  setUpAll(() async {
    await AppLogger.init(logDirFactory: () async => null);
  });

  // ---------------------------------------------------------------------------
  // renderTemplateExample — pure function tests
  // ---------------------------------------------------------------------------

  group('renderTemplateExample', () {
    test('pads and substitutes numeric placeholder', () {
      expect(
        renderTemplateExample('{series} #{number:03} ({year})'),
        'Saga #007 (2013)',
      );
    });

    test('collapses unknown key and orphaned literals', () {
      // {nope} is not in sample fields → placeholder + adjacent parens dropped
      expect(renderTemplateExample('{series} ({nope})'), 'Saga');
    });

    test('substitutes known fields without padding', () {
      expect(renderTemplateExample('{series} - {title}'), 'Saga - Chapter Seven');
    });

    test('collapses unknown key between literals', () {
      // brackets with only unknown key content collapse
      expect(renderTemplateExample('{series} [{unknown}]'), 'Saga');
    });

    test('volume field substitutes correctly', () {
      expect(renderTemplateExample('{series} Vol. {volume}'), 'Saga Vol. 2');
    });

    test('non-numeric value with pad format passes through unpadded', () {
      // number sample is '7' (integer string), pad 03 → '007'
      // But if we ask for {year:04} where year='2013' (4 chars already), no pad needed
      expect(renderTemplateExample('{year:04}'), '2013');
    });

    test('format field substitutes correctly', () {
      expect(renderTemplateExample('{series} ({format})'), 'Saga (TPB)');
    });

    test('stray separator trimmed from ends', () {
      // If trailing '-' or '#' results from collapse, trim it
      expect(renderTemplateExample('{series} - {nope}'), 'Saga');
    });
  });

  // ---------------------------------------------------------------------------
  // RenameTemplatesNotifier — provider tests
  // ---------------------------------------------------------------------------

  group('RenameTemplatesNotifier', () {
    late List<http.Request> requests;

    ProviderContainer makeContainer(MockClient mockClient) {
      requests = [];
      return ProviderContainer(overrides: [
        apiClientProvider.overrideWithValue(ApiClient(
          baseUrl: 'http://test',
          deviceId: 'test-device',
          httpClient: mockClient,
        )),
      ]);
    }

    test('loads templates from GET /rename-templates', () async {
      final container = makeContainer(MockClient((req) async {
        requests.add(req);
        return http.Response(
          jsonEncode({'templates': {'tpb': '{series} Vol. {number}'}}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }));
      addTearDown(container.dispose);

      final result = await container.read(renameTemplatesProvider.future);
      expect(result, {'tpb': '{series} Vol. {number}'});
      expect(requests.single.method, 'GET');
      expect(requests.single.url.path, '/rename-templates');
    });

    test('save() PUTs correct body then reloads', () async {
      var getCount = 0;
      final container = makeContainer(MockClient((req) async {
        requests.add(req);
        if (req.method == 'GET') {
          getCount++;
          return http.Response(
            jsonEncode({'templates': getCount == 1
                ? {'tpb': 'old'}
                : {'tpb': 'new'}}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        // PUT
        return http.Response('', 204);
      }));
      addTearDown(container.dispose);

      // Initial load
      final first = await container.read(renameTemplatesProvider.future);
      expect(first['tpb'], 'old');

      // Save
      final notifier =
          container.read(renameTemplatesProvider.notifier);
      await notifier.save({'tpb': 'new'});

      // Verify PUT request
      final putReq = requests.firstWhere((r) => r.method == 'PUT');
      expect(putReq.url.path, '/rename-templates');
      expect(jsonDecode(putReq.body), {'templates': {'tpb': 'new'}});

      // After invalidateSelf, re-read should reflect new value
      final second = await container.read(renameTemplatesProvider.future);
      expect(second['tpb'], 'new');
    });
  });
}
