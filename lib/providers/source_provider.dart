import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/server_source.dart';
import 'providers.dart';

const _sourcesKey = 'server_sources';
const _activeSourceKey = 'active_source_id';
const _credentialPrefix = 'source_cred_';
const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

/// The push-registration key baked in by `make ipad` (read from the server's
/// register_secret on the build Mac), so a reinstall needs no typing. Seeds a
/// fresh install and fills in a keyless default source on an existing one;
/// a key set in Settings → API Key wins. (Clearing it there only lasts until
/// the next launch of a build that carries a built-in key.)
/// ponytail: the secret ships inside the app; fine for a sideloaded,
/// own-devices-only build.
@visibleForTesting
String builtInApiKey = const String.fromEnvironment('PUSH_API_KEY');

typedef SourceCredentials = ({String? password, String? apiKey});

/// Every saved source's secrets from secure storage, keyed by source id.
/// `toJson` leaves them out of SharedPreferences, so main() reads them before
/// runApp and overrides [sourceCredentialsProvider] with the result: then
/// [SourceListNotifier.build] returns complete sources synchronously, and the
/// launch drain, download-journal restore, first cover sweep and first scan
/// poll all send real auth.
Future<Map<String, SourceCredentials>> readSourceCredentials(
    SharedPreferences prefs) async {
  final raw = prefs.getString(_sourcesKey);
  if (raw == null) return const {};
  final creds = <String, SourceCredentials>{};
  try {
    for (final e in jsonDecode(raw) as List<dynamic>) {
      final id = (e as Map<String, dynamic>)['id'] as String;
      creds[id] = (
        password:
            await _secureStorage.read(key: '$_credentialPrefix${id}_password'),
        apiKey:
            await _secureStorage.read(key: '$_credentialPrefix${id}_apiKey'),
      );
    }
  } catch (e) {
    // A locked or broken keychain must not stop the app launching; the
    // sources just start without secrets (the server answers 401).
    debugPrint('readSourceCredentials failed: $e');
  }
  return creds;
}

/// Overridden in main() with [readSourceCredentials]; empty by default (tests,
/// fresh installs).
final sourceCredentialsProvider =
    Provider<Map<String, SourceCredentials>>((ref) => const {});

class SourceListNotifier extends Notifier<List<ServerSource>> {
  SharedPreferences get _prefs => ref.read(sharedPrefsProvider);

  @override
  List<ServerSource> build() {
    final raw = _prefs.getString(_sourcesKey);
    if (raw != null) {
      final list = (jsonDecode(raw) as List<dynamic>)
          .map((e) => ServerSource.fromJson(e as Map<String, dynamic>))
          .toList();
      if (list.isNotEmpty) return _withCredentials(list);
    }
    // Seed with default custom backend source
    final config = ref.read(serverConfigProvider);
    var defaultSource = ServerSource.createDefault(url: config.serverUrl);
    if (builtInApiKey.isNotEmpty) {
      defaultSource = defaultSource.copyWith(
          authType: AuthType.apiKey, apiKey: builtInApiKey);
    }
    _persist([defaultSource]);
    return [defaultSource];
  }

  List<ServerSource> _withCredentials(List<ServerSource> sources) {
    final creds = ref.read(sourceCredentialsProvider);
    final updated = [
      for (final s in sources)
        s.copyWith(
          password: creds[s.id]?.password ?? s.password,
          apiKey: creds[s.id]?.apiKey ?? s.apiKey,
        ),
    ];
    // An install over an older build keeps its saved sources, so the seed
    // above never runs: give a keyless default source the built-in key too.
    var seeded = false;
    if (builtInApiKey.isNotEmpty) {
      for (var i = 0; i < updated.length; i++) {
        final s = updated[i];
        if (s.isDefault && (s.apiKey ?? '').isEmpty) {
          updated[i] =
              s.copyWith(authType: AuthType.apiKey, apiKey: builtInApiKey);
          seeded = true;
        }
      }
    }
    if (seeded) _persist(updated);
    return updated;
  }

  void add(ServerSource source) {
    state = [...state, source];
    _persist(state);
  }

  void edit(String id, ServerSource updated) {
    state = [
      for (final s in state)
        if (s.id == id) updated else s,
    ];
    _persist(state);
  }

  void remove(String id) {
    state = state.where((s) => s.id != id).toList();
    _persist(state);
    _secureStorage.delete(key: '$_credentialPrefix${id}_password');
    _secureStorage.delete(key: '$_credentialPrefix${id}_apiKey');
  }

  void updateDefaultUrl(String url) {
    state = [
      for (final s in state)
        if (s.isDefault) s.copyWith(baseUrl: url) else s,
    ];
    _persist(state);
  }

  /// Sets (or, when empty, clears) the default server's API key. The server
  /// requires it to register this device for push notifications.
  void updateDefaultApiKey(String key) {
    state = [
      for (final s in state)
        if (s.isDefault)
          ServerSource(
            id: s.id,
            name: s.name,
            type: s.type,
            baseUrl: s.baseUrl,
            authType: key.isEmpty ? AuthType.none : AuthType.apiKey,
            apiKey: key.isEmpty ? null : key,
            isDefault: true,
          )
        else
          s,
    ];
    _persist(state);
  }

  /// Sets the default server's Basic credentials (the password goes to secure
  /// storage via [_persist]).
  void updateDefaultBasicAuth(String username, String password) {
    state = [
      for (final s in state)
        if (s.isDefault)
          ServerSource(
            id: s.id,
            name: s.name,
            type: s.type,
            baseUrl: s.baseUrl,
            authType: AuthType.basic,
            username: username,
            password: password,
            isDefault: true,
          )
        else
          s,
    ];
    _persist(state);
  }

  void _persist(List<ServerSource> sources) {
    _prefs.setString(
      _sourcesKey,
      jsonEncode(sources.map((s) => s.toJson()).toList()),
    );
    // Persist credentials in secure storage
    for (final s in sources) {
      if (s.password != null) {
        _secureStorage.write(
            key: '$_credentialPrefix${s.id}_password', value: s.password!);
      } else {
        _secureStorage.delete(key: '$_credentialPrefix${s.id}_password');
      }
      if (s.apiKey != null) {
        _secureStorage.write(
            key: '$_credentialPrefix${s.id}_apiKey', value: s.apiKey!);
      } else {
        _secureStorage.delete(key: '$_credentialPrefix${s.id}_apiKey');
      }
    }
  }
}

final sourceListProvider =
    NotifierProvider<SourceListNotifier, List<ServerSource>>(
        SourceListNotifier.new);

class ActiveSourceNotifier extends Notifier<String> {
  @override
  String build() {
    final prefs = ref.read(sharedPrefsProvider);
    return prefs.getString(_activeSourceKey) ?? 'default';
  }

  void select(String sourceId) {
    state = sourceId;
    ref.read(sharedPrefsProvider).setString(_activeSourceKey, sourceId);
  }
}

final activeSourceIdProvider =
    NotifierProvider<ActiveSourceNotifier, String>(ActiveSourceNotifier.new);

/// Derived provider: the currently active ServerSource object.
final activeSourceProvider = Provider<ServerSource>((ref) {
  final sources = ref.watch(sourceListProvider);
  final activeId = ref.watch(activeSourceIdProvider);
  return sources.firstWhere(
    (s) => s.id == activeId,
    orElse: () => sources.first,
  );
});

/// Helper to generate a UUID for new sources.
String generateSourceId() => const Uuid().v4();
