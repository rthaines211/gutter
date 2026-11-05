import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class ServerConfig {
  final SharedPreferences _prefs;

  ServerConfig(this._prefs);

  static const _serverUrlKey = 'server_url';
  static const _deviceIdKey = 'device_id';
  // Empty in public builds; the personal build passes it via Makefile.local.
  static const _defaultServerUrl = String.fromEnvironment('DEFAULT_SERVER_URL');

  String get serverUrl =>
      _prefs.getString(_serverUrlKey) ?? _defaultServerUrl;

  Future<void> setServerUrl(String url) =>
      _prefs.setString(_serverUrlKey, url);

  String get deviceId {
    final existing = _prefs.getString(_deviceIdKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final newId = const Uuid().v4();
    _prefs.setString(_deviceIdKey, newId);
    return newId;
  }
}
