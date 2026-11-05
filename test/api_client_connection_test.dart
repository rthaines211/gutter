import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:comic_reader_app/services/api_client.dart';
import 'package:comic_reader_app/services/app_logger.dart';

void main() {
  setUp(() async {
    await AppLogger.init(logDirFactory: () async => null);
  });

  tearDown(() {
    AppLogger.resetForTest();
  });

  group('ApiClient.checkConnection', () {
    test('returns true when server responds 200', () async {
      final mockClient = MockClient((request) async {
        return http.Response('[]', 200);
      });
      final client = ApiClient(
        baseUrl: 'http://localhost:8080',
        deviceId: 'test',
        httpClient: mockClient,
      );
      expect(await client.checkConnection(), isTrue);
    });

    test('returns false when server responds with error', () async {
      final mockClient = MockClient((request) async {
        return http.Response('error', 500);
      });
      final client = ApiClient(
        baseUrl: 'http://localhost:8080',
        deviceId: 'test',
        httpClient: mockClient,
      );
      expect(await client.checkConnection(), isFalse);
    });

    test('returns false when request throws', () async {
      final mockClient = MockClient((request) async {
        throw Exception('Connection refused');
      });
      final client = ApiClient(
        baseUrl: 'http://localhost:8080',
        deviceId: 'test',
        httpClient: mockClient,
      );
      expect(await client.checkConnection(), isFalse);
    });
  });

  group('ApiClient.onRequestOutcome callback', () {
    test('fires true on 2xx', () async {
      final outcomes = <bool>[];
      final client = ApiClient(
        baseUrl: 'http://localhost:8080',
        deviceId: 'test',
        httpClient: MockClient((_) async => http.Response('[]', 200)),
        onRequestOutcome: outcomes.add,
      );
      await client.checkConnection();
      expect(outcomes, [true]);
    });

    test('fires true on 4xx (server reached)', () async {
      final outcomes = <bool>[];
      final client = ApiClient(
        baseUrl: 'http://localhost:8080',
        deviceId: 'test',
        httpClient: MockClient((_) async => http.Response('not found', 404)),
        onRequestOutcome: outcomes.add,
      );
      await client.checkConnection();
      expect(outcomes, [true]);
    });

    test('fires true on 5xx (server reached)', () async {
      final outcomes = <bool>[];
      final client = ApiClient(
        baseUrl: 'http://localhost:8080',
        deviceId: 'test',
        httpClient: MockClient((_) async => http.Response('boom', 500)),
        onRequestOutcome: outcomes.add,
      );
      await client.checkConnection();
      expect(outcomes, [true]);
    });

    test('fires false on SocketException', () async {
      final outcomes = <bool>[];
      final client = ApiClient(
        baseUrl: 'http://localhost:8080',
        deviceId: 'test',
        httpClient: MockClient((_) async {
          throw const SocketException('refused');
        }),
        onRequestOutcome: outcomes.add,
      );
      await client.checkConnection();
      expect(outcomes, [false]);
    });

    test('fires false on TimeoutException', () async {
      final outcomes = <bool>[];
      final client = ApiClient(
        baseUrl: 'http://localhost:8080',
        deviceId: 'test',
        httpClient: MockClient((_) async {
          throw TimeoutException('slow');
        }),
        onRequestOutcome: outcomes.add,
      );
      await client.checkConnection();
      expect(outcomes, [false]);
    });

    test('fires false on HandshakeException', () async {
      final outcomes = <bool>[];
      final client = ApiClient(
        baseUrl: 'http://localhost:8080',
        deviceId: 'test',
        httpClient: MockClient((_) async {
          throw const HandshakeException('bad cert');
        }),
        onRequestOutcome: outcomes.add,
      );
      await client.checkConnection();
      expect(outcomes, [false]);
    });

    test('fires false on http.ClientException', () async {
      final outcomes = <bool>[];
      final client = ApiClient(
        baseUrl: 'http://localhost:8080',
        deviceId: 'test',
        httpClient: MockClient((_) async {
          throw http.ClientException('network unavailable');
        }),
        onRequestOutcome: outcomes.add,
      );
      await client.checkConnection();
      expect(outcomes, [false]);
    });

    test('does not fire on non-network exceptions', () async {
      final outcomes = <bool>[];
      final client = ApiClient(
        baseUrl: 'http://localhost:8080',
        deviceId: 'test',
        httpClient: MockClient((_) async {
          throw ArgumentError('not a network error');
        }),
        onRequestOutcome: outcomes.add,
      );
      await client.checkConnection();
      // checkConnection's outer catch swallows it and returns false, but the
      // callback must not have fired since this is not a network-layer error.
      expect(outcomes, isEmpty);
    });
  });
}
