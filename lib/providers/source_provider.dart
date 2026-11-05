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
/// register_secret on the build Mac), so a reinstall needs no typing. Only
/// seeds a fresh install; Settings → API Key still overrides or clears it.
/// ponytail: the secret ships inside the app; fine for a sideloaded,
/// own-devices-only build.
@visibleForTesting
String builtInApiKey = const String.fromEnvironment('PUSH_API_KEY');

class SourceListNotifier extends Notifier<List<ServerSource>> {
  SharedPreferences get _prefs => ref.read(sharedPrefsProvider);

  @override
  List<ServerSource> build() {
    final raw = _prefs.getString(_sourcesKey);
    if (raw != null) {
      final list = (jsonDecode(raw) as List<dynamic>)
          .map((e) => ServerSource.fromJson(e as Map<String, dynamic>))
          .toList();
      if (list.isNotEmpty) {
        _loadCredentials(list);
        return list;
      }
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

  Future<void> _loadCredentials(List<ServerSource> sources) async {
    final updated = <ServerSource>[];
    for (final s in sources) {
      final password =
          await _secureStorage.read(key: '$_credentialPrefix${s.id}_password');
      final apiKey =
          await _secureStorage.read(key: '$_credentialPrefix${s.id}_apiKey');
      if (password != null || apiKey != null) {
        updated.add(s.copyWith(
          password: password ?? s.password,
          apiKey: apiKey ?? s.apiKey,
        ));
      } else {
        updated.add(s);
      }
    }
    state = updated;
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
