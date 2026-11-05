import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/local_session_store.dart';
import 'cache_providers.dart';
import '../services/source_auth_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/server_config.dart';
import '../models/server_source.dart';
import '../services/api_client.dart';
import '../services/komga_client.dart';
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

/// Client for the active source: [KomgaClient] for Komga, else the Gutter
/// server's [ApiClient].
/// Rebuilds when active source changes.
final apiClientProvider = Provider<ApiClient>((ref) {
  return clientFor(
    ref.watch(activeSourceProvider),
    deviceId: ref.watch(serverConfigProvider).deviceId,
    sessions: ref.watch(localSessionStoreProvider),
    onRequestOutcome: (reachedServer) =>
        ref.read(connectivityProvider.notifier).reportOutcome(reachedServer),
  );
});

/// The client for [source]'s server type, carrying its credentials.
ApiClient clientFor(ServerSource source,
        {required String deviceId,
        RequestOutcomeCallback? onRequestOutcome,
        LocalSessionStore? sessions}) =>
    source.type == SourceType.komga
        ? KomgaClient(
            baseUrl: source.baseUrl,
            deviceId: deviceId,
            authHeaders: source.authHeaders,
            onRequestOutcome: onRequestOutcome,
            sessions: sessions,
          )
        : ApiClient(
            baseUrl: source.baseUrl,
            deviceId: deviceId,
            authHeaders: source.authHeaders,
            onRequestOutcome: onRequestOutcome,
          );

/// Client for the panel label server, proxied at `<baseUrl>/labeller/`.
final labelClientProvider = Provider<LabelClient>((ref) {
  return LabelClient(baseUrl: ref.watch(apiClientProvider).baseUrl);
});

/// Whether the active source is a custom backend (vs OPDS).
final isCustomSourceProvider = Provider<bool>((ref) {
  final source = ref.watch(activeSourceProvider);
  return source.type == SourceType.custom;
});

/// Points [SourceAuthClient] (image loads, cover sync) at the active source
/// and its credentials. Watched by the app root.
final sourceAuthSyncProvider = Provider<void>((ref) {
  final source = ref.watch(activeSourceProvider);
  SourceAuthClient.use(source.baseUrl, source.authHeaders);
});

/// Whether the active source syncs into the mirror (Gutter server or Komga).
final hasMirrorProvider = Provider<bool>((ref) {
  return ref.watch(activeSourceProvider).type != SourceType.opds;
});
