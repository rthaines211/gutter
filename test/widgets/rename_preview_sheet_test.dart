// test/widgets/rename_preview_sheet_test.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:comic_reader_app/providers/providers.dart';
import 'package:comic_reader_app/providers/mirror_provider.dart';
import 'package:comic_reader_app/services/api_client.dart';
import 'package:comic_reader_app/services/app_logger.dart';
import 'package:comic_reader_app/widgets/rename_preview_sheet.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Builds a dry-run response with one clean rename and one conflict.
http.Response _dryRunResponse() => http.Response(
      jsonEncode({
        'results': [
          {
            'issue_id': 'i1',
            'old_name': 'Batman 001.cbz',
            'new_name': 'Batman #001.cbz',
            'conflict': false,
            'applied': false,
          },
          {
            'issue_id': 'i2',
            'old_name': 'Batman 002.cbz',
            'new_name': 'Batman #002.cbz',
            'conflict': true,
            'applied': false,
          },
        ],
      }),
      200,
      headers: {'content-type': 'application/json'},
    );

/// Builds the apply (non-dry-run) response — one applied, one conflict skipped.
http.Response _applyResponse() => http.Response(
      jsonEncode({
        'results': [
          {
            'issue_id': 'i1',
            'old_name': 'Batman 001.cbz',
            'new_name': 'Batman #001.cbz',
            'conflict': false,
            'applied': true,
          },
          {
            'issue_id': 'i2',
            'old_name': 'Batman 002.cbz',
            'new_name': 'Batman #002.cbz',
            'conflict': true,
            'applied': false,
          },
        ],
      }),
      200,
      headers: {'content-type': 'application/json'},
    );

/// Records which URLs were called.
class _RequestLog {
  final List<String> urls = [];
}

Widget _buildSheet({required _RequestLog log}) {
  final mockClient = MockClient((req) async {
    log.urls.add(req.url.toString());
    if (req.url.queryParameters['dry_run'] == '1') {
      return _dryRunResponse();
    }
    return _applyResponse();
  });

  final apiClient = ApiClient(
    baseUrl: 'http://localhost:8080',
    deviceId: 'test-device',
    httpClient: mockClient,
  );

  return ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(apiClient),
      // Stub out syncEngineProvider so the widget can read it without crashing.
      syncEngineProvider.overrideWithValue(null),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: RenamePreviewSheet(
          seriesId: 's1',
          accent: Colors.blue,
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(() async {
    await AppLogger.init(logDirFactory: () async => null);
  });

  testWidgets('preview lists renames and flags conflicts', (tester) async {
    final log = _RequestLog();
    await tester.pumpWidget(_buildSheet(log: log));

    // Pump past initState future
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Both old→new rows should be visible
    expect(find.text('Batman 001'), findsOneWidget); // stripComicExtension
    expect(find.text('Batman #001'), findsOneWidget);
    expect(find.text('Batman 002'), findsOneWidget);
    expect(find.text('Batman #002'), findsOneWidget);

    // Conflict chip on the second row
    expect(find.text('conflict'), findsOneWidget);

    // Apply button shows N=1 (only the clean rename counts)
    expect(find.text('Apply 1 rename'), findsOneWidget);

    // Dry-run request was made
    expect(log.urls.any((u) => u.contains('dry_run=1')), isTrue);
  });

  testWidgets('apply calls non-dry endpoint', (tester) async {
    final log = _RequestLog();
    await tester.pumpWidget(_buildSheet(log: log));

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Tap the Apply button
    await tester.tap(find.text('Apply 1 rename'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // A second request WITHOUT dry_run=1 should have been made
    final nonDryRequests = log.urls.where((u) =>
        u.contains('apply-template') && !u.contains('dry_run=1'));
    expect(nonDryRequests, isNotEmpty);
  });
}
