import 'package:flutter/widgets.dart';
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

/// Auth headers for an image at [url]: the active source's credentials when
/// [url] is on that source's server, nothing otherwise. Creator, review and
/// volume sheets show raw ComicVine/Metron image URLs, which must not get the
/// server password. The boundary check stops `https://my.server.evil.com`
/// passing as `https://my.server`.
Map<String, String> imageHeadersFor(ServerSource source, String url) {
  var base = source.baseUrl;
  while (base.endsWith('/')) {
    base = base.substring(0, base.length - 1);
  }
  if (base.isEmpty) return const {};
  final sameOrigin = url == base ||
      url.startsWith('$base/') ||
      url.startsWith('$base?');
  return sameOrigin ? source.authHeaders : const {};
}

/// [imageHeadersFor] the active source, for widgets without a `ref` (read once
/// per build).
Map<String, String> imageHeadersOf(BuildContext context, String url) =>
    imageHeadersFor(
        ProviderScope.containerOf(context).read(activeSourceProvider), url);

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
