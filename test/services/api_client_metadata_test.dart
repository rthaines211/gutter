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
      baseUrl: 'http://x',
      deviceId: 'test',
      httpClient: MockClient((req) async {
        requests.add(req);
        return http.Response(body, status);
      }),
    );
  }

  test('patchComicMetadata sends PATCH with only provided fields', () async {
    final client = clientReturning(204, '');
    await client.patchComicMetadata('c1', {'title': 'T', 'format': 'tpb'});
    final req = requests.single;
    expect(req.method, 'PATCH');
    expect(req.url.path, '/comics/c1/metadata');
    expect(jsonDecode(req.body), {'title': 'T', 'format': 'tpb'});
  });

  test('patchSeriesMetadata throws ApiException on 404', () async {
    final client = clientReturning(404, 'series not found');
    await expectLater(
      () => client.patchSeriesMetadata('nope', {'publisher': 'P'}),
      throwsA(isA<ApiException>()),
    );
  });

  test('renameSeriesFolder returns new id and maps 409', () async {
    var client = clientReturning(200, '{"id":"new-id","name":"New Name"}');
    final result = await client.renameSeriesFolder('old-id', 'New Name');
    expect(result, {'id': 'new-id', 'name': 'New Name'});
    final req = requests.single;
    expect(req.method, 'PUT');
    expect(jsonDecode(req.body), {'name': 'New Name'});

    client = clientReturning(409, 'exists');
    expect(() => client.renameSeriesFolder('old-id', 'X'),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 409)));
  });

  test('applyTemplate parses results and passes dry_run', () async {
    var client = clientReturning(200,
        '{"results":[{"issue_id":"i1","old_name":"a.cbz","new_name":"Series #001.cbz","conflict":false,"applied":false}]}');
    var results = await client.applyTemplate('s1', dryRun: true);
    expect(requests.single.url.query, contains('dry_run=1'));
    expect(results.single.newName, 'Series #001.cbz');
    expect(results.single.conflict, isFalse);

    client = clientReturning(200,
        '{"results":[{"issue_id":"i1","old_name":"a.cbz","new_name":"Series #001.cbz","conflict":false,"applied":true}]}');
    results = await client.applyTemplate('s1', dryRun: false);
    expect(requests.single.url.queryParameters.containsKey('dry_run'), isFalse);
    expect(results.single.applied, isTrue);
  });

  test('rename templates round trip', () async {
    var client = clientReturning(200, '{"templates":{"tpb":"{series} Vol. {number}"}}');
    final templates = await client.fetchRenameTemplates();
    expect(templates['tpb'], '{series} Vol. {number}');

    client = clientReturning(204, '');
    await client.saveRenameTemplates({'tpb': 'x'});
    expect(requests.single.method, 'PUT');
    expect(jsonDecode(requests.single.body), {'templates': {'tpb': 'x'}});
  });
}
