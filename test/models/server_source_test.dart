import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/models/server_source.dart';

void main() {
  group('ServerSource', () {
    test('toJson and fromJson round-trip for custom source', () {
      final source = ServerSource(
        id: 'abc-123',
        name: 'My Server',
        type: SourceType.custom,
        baseUrl: 'http://192.168.1.10:8080',
        authType: AuthType.none,
      );
      final json = source.toJson();
      final restored = ServerSource.fromJson(json);
      expect(restored.id, 'abc-123');
      expect(restored.name, 'My Server');
      expect(restored.type, SourceType.custom);
      expect(restored.baseUrl, 'http://192.168.1.10:8080');
      expect(restored.authType, AuthType.none);
      expect(restored.username, isNull);
      expect(restored.password, isNull);
      expect(restored.apiKey, isNull);
    });

    test('toJson excludes credentials (stored in secure storage)', () {
      final source = ServerSource(
        id: 'opds-1',
        name: 'Kavita',
        type: SourceType.opds,
        baseUrl: 'https://kavita.local/api/opds/abc',
        authType: AuthType.basic,
        username: 'admin',
        password: 'hunter2',
      );
      final json = source.toJson();
      // password must not be serialized to SharedPreferences JSON
      expect(json.containsKey('password'), isFalse);
      expect(json.containsKey('api_key'), isFalse);
      // non-sensitive fields are still present
      expect(json['username'], 'admin');
      expect(json['auth_type'], 'basic');
    });

    test('toJson/fromJson round-trip: credentials null after deserialization', () {
      final source = ServerSource(
        id: 'opds-1',
        name: 'Kavita',
        type: SourceType.opds,
        baseUrl: 'https://kavita.local/api/opds/abc',
        authType: AuthType.basic,
        username: 'admin',
        password: 'hunter2',
      );
      final restored = ServerSource.fromJson(source.toJson());
      expect(restored.type, SourceType.opds);
      expect(restored.authType, AuthType.basic);
      expect(restored.username, 'admin');
      // password stripped from JSON — secure storage handles it at runtime
      expect(restored.password, isNull);
    });

    test('toJson excludes apiKey (stored in secure storage)', () {
      final source = ServerSource(
        id: 'opds-2',
        name: 'Komga',
        type: SourceType.opds,
        baseUrl: 'https://komga.local/opds/v1.2',
        authType: AuthType.apiKey,
        apiKey: 'sk-abc123',
      );
      final json = source.toJson();
      expect(json.containsKey('api_key'), isFalse);
      final restored = ServerSource.fromJson(json);
      expect(restored.authType, AuthType.apiKey);
      // apiKey stripped from JSON — secure storage handles it at runtime
      expect(restored.apiKey, isNull);
    });

    test('createDefault produces a custom source with given URL', () {
      final source = ServerSource.createDefault(
        url: 'http://10.0.0.5:8080',
      );
      expect(source.id, isNotEmpty);
      expect(source.name, 'My Server');
      expect(source.type, SourceType.custom);
      expect(source.baseUrl, 'http://10.0.0.5:8080');
      expect(source.isDefault, isTrue);
    });

    test('authHeaders returns empty map for no auth', () {
      final source = ServerSource(
        id: 'x', name: 'X', type: SourceType.opds,
        baseUrl: 'http://x', authType: AuthType.none,
      );
      expect(source.authHeaders, isEmpty);
    });

    test('authHeaders returns basic auth header', () {
      final source = ServerSource(
        id: 'x', name: 'X', type: SourceType.opds,
        baseUrl: 'http://x', authType: AuthType.basic,
        username: 'user', password: 'pass',
      );
      final headers = source.authHeaders;
      expect(headers['Authorization'], startsWith('Basic '));
    });

    test('authHeaders returns API key header', () {
      final source = ServerSource(
        id: 'x', name: 'X', type: SourceType.opds,
        baseUrl: 'http://x', authType: AuthType.apiKey,
        apiKey: 'my-key',
      );
      final headers = source.authHeaders;
      expect(headers['Authorization'], 'Bearer my-key');
    });
  });
}
