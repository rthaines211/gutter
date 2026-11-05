import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:comic_reader_app/providers/providers.dart';
import 'package:comic_reader_app/screens/rename_templates_screen.dart';
import 'package:comic_reader_app/services/api_client.dart';
import 'package:comic_reader_app/services/app_logger.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _kTemplatesResponse = {
  'templates': {
    'single': '{series} #{number:03} ({year})',
    'tpb': '{series} Vol. {number} ({year})',
    'default': '{series} #{number:03}',
  }
};

/// Build a [ProviderScope] with an overridden [apiClientProvider] backed by
/// [mockClient], wrapping [RenameTemplatesScreen] in a [MaterialApp].
Widget _makeScreen(MockClient mockClient) {
  return ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(ApiClient(
        baseUrl: 'http://test',
        deviceId: 'test-device',
        httpClient: mockClient,
      )),
    ],
    child: const MaterialApp(
      home: RenameTemplatesScreen(),
    ),
  );
}

void main() {
  setUpAll(() async {
    await AppLogger.init(logDirFactory: () async => null);
  });

  // -------------------------------------------------------------------------
  // Test 1: renders fields from loaded provider
  // -------------------------------------------------------------------------

  testWidgets('renders tpb TextField and live preview after load',
      (tester) async {
    final mockClient = MockClient((req) async {
      return http.Response(
        jsonEncode(_kTemplatesResponse),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    await tester.pumpWidget(_makeScreen(mockClient));
    // Let the async provider resolve and post-frame callbacks fire.
    await tester.pumpAndSettle();

    // The tpb TextField should contain the loaded template text.
    final tpbField = find.byKey(const ValueKey('template_field_tpb'));
    expect(tpbField, findsOneWidget);
    expect(
      tester.widget<TextField>(tpbField).controller!.text,
      '{series} Vol. {number} ({year})',
    );

    // Live preview for tpb template: {series} Vol. {number} ({year})
    // renderTemplateExample substitutes: series=Saga, number=7, year=2013
    // → "Saga Vol. 7 (2013)"
    expect(find.textContaining('Saga Vol. 7 (2013)'), findsOneWidget);
  });

  // -------------------------------------------------------------------------
  // Test 2: save calls PUT /rename-templates with all fields + shows SnackBar
  // -------------------------------------------------------------------------

  testWidgets('editing tpb and tapping Save PUTs updated templates',
      (tester) async {
    final requests = <http.Request>[];

    final mockClient = MockClient((req) async {
      requests.add(req);
      if (req.method == 'GET') {
        return http.Response(
          jsonEncode(_kTemplatesResponse),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      // PUT /rename-templates
      return http.Response('', 204);
    });

    await tester.pumpWidget(_makeScreen(mockClient));
    await tester.pumpAndSettle();

    // Edit the tpb field.
    const newTpbTemplate = '{series} TP {number}';
    await tester.enterText(
      find.byKey(const ValueKey('template_field_tpb')),
      newTpbTemplate,
    );
    await tester.pumpAndSettle();

    // Tap the Save AppBar action.
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // Verify a PUT to /rename-templates was recorded.
    final putReqs =
        requests.where((r) => r.method == 'PUT').toList();
    expect(putReqs, isNotEmpty, reason: 'Expected at least one PUT request');

    final putReq = putReqs.first;
    expect(putReq.url.path, '/rename-templates');

    final body = jsonDecode(putReq.body) as Map<String, dynamic>;
    final templates = body['templates'] as Map<String, dynamic>;
    expect(templates['tpb'], newTpbTemplate);

    // Success SnackBar should appear.
    expect(find.text('Rename templates saved'), findsOneWidget);
  });
}
