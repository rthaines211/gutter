import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:comic_reader_app/services/api_client.dart';
import 'package:comic_reader_app/services/app_logger.dart';

void main() {
  setUpAll(() async {
    await AppLogger.init(logDirFactory: () async => null);
  });

  late List<http.Request> requests;

  ApiClient clientReturning(int status, String body) {
    requests = [];
    return ApiClient(
      baseUrl: 'http://test',
      deviceId: 'd',
      httpClient: MockClient((req) async {
        requests.add(req);
        return http.Response(body, status);
      }),
    );
  }

  test('fetchCreators parses list of summaries', () async {
    final client = clientReturning(
      200,
      jsonEncode([
        {
          'id': 40724,
          'name': 'Tom King',
          'roles': ['writer'],
          'seriesIds': ['s1', 's2'],
        }
      ]),
    );
    final result = await client.fetchCreators();
    expect(result.single.id, 40724);
    expect(result.single.name, 'Tom King');
    expect(result.single.roles, ['writer']);
    expect(result.single.seriesIds, ['s1', 's2']);
    expect(requests.single.url.path, '/creators');
  });

  test('fetchCreator parses a full profile', () async {
    final client = clientReturning(
      200,
      jsonEncode({
        'id': 40724,
        'name': 'Tom King',
        'roles': ['writer'],
        'seriesIds': ['s1'],
        'volumesOwned': 1,
        'volumesTotal': 2,
        'bibliography': null,
        'bibliographyPending': true,
      }),
    );
    final result = await client.fetchCreator(40724);
    expect(result, isNotNull);
    expect(result!.id, 40724);
    expect(result.bibliography, isNull);
    expect(result.bibliographyPending, true);
    expect(requests.single.url.path, '/creators/40724');
  });

  test('fetchCreator returns null on 404', () async {
    final client = clientReturning(404, jsonEncode({'error': 'not found'}));
    final result = await client.fetchCreator(1);
    expect(result, isNull);
  });

  test('lookupCreator parses matches and encodes name query', () async {
    final client = clientReturning(
      200,
      jsonEncode([
        {'id': 1, 'name': 'Tom King', 'volumes': 3},
      ]),
    );
    final result = await client.lookupCreator('Tom King');
    expect(result.single.id, 1);
    expect(result.single.volumes, 3);
    expect(requests.single.url.path, '/creators/lookup');
    expect(requests.single.url.queryParameters['name'], 'Tom King');
  });

  test('fetchVolumeInfo parses VolumeInfo', () async {
    final client = clientReturning(
      200,
      jsonEncode({
        'volumeId': 9,
        'name': 'Batman',
        'startYear': 2016,
        'publisher': 'DC',
        'coverUrl': 'http://x/c.jpg',
        'totalIssues': 24,
        'description': 'The Dark Knight.',
      }),
    );
    final result = await client.fetchVolumeInfo(9);
    expect(result.volumeId, 9);
    expect(result.description, 'The Dark Knight.');
    expect(requests.single.url.path, '/creators/volumes/9');
  });

  test('fetchIssueCredits parses list of Creator', () async {
    final client = clientReturning(
      200,
      jsonEncode([
        {'id': 40724, 'name': 'Tom King', 'role': 'writer'},
      ]),
    );
    final result = await client.fetchIssueCredits('c1');
    expect(result, isNotNull);
    expect(result!.single.name, 'Tom King');
    expect(result.single.role, 'writer');
    expect(requests.single.url.path, '/creators/issues/c1');
  });

  test('fetchIssueCredits returns null on 404', () async {
    final client = clientReturning(404, jsonEncode({'error': 'no cv id'}));
    final result = await client.fetchIssueCredits('c1');
    expect(result, isNull);
  });
}
