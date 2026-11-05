import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/server_config.dart';
import '../models/server_source.dart';
import '../services/api_client.dart';
import '../services/label_client.dart';
import 'connectivity_provider.dart';
import 'source_provider.dart';

final sharedPrefsProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('Must be overridden in main');
});

final serverConfigProvider = Provider<ServerConfig>((ref) {
  final prefs = ref.watch(sharedPrefsProvider);
  return ServerConfig(prefs);
});

/// ApiClient for the custom backend. Only valid when active source is custom.
/// Rebuilds when active source changes.
final apiClientProvider = Provider<ApiClient>((ref) {
  final source = ref.watch(activeSourceProvider);
  final config = ref.watch(serverConfigProvider);
  return ApiClient(
    baseUrl: source.baseUrl,
    deviceId: config.deviceId,
    authHeaders: source.authHeaders,
    onRequestOutcome: (reachedServer) {
      ref.read(connectivityProvider.notifier).reportOutcome(reachedServer);
    },
  );
});

/// Client for the panel label server, proxied at `<baseUrl>/labeller/`.
final labelClientProvider = Provider<LabelClient>((ref) {
  final api = ref.watch(apiClientProvider);
  return LabelClient(baseUrl: api.baseUrl, authHeaders: api.authHeaders);
});

/// Whether the active source is a custom backend (vs OPDS).
final isCustomSourceProvider = Provider<bool>((ref) {
  final source = ref.watch(activeSourceProvider);
  return source.type == SourceType.custom;
});
