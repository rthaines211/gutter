import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/app_theme.dart';
import '../config/flavor.dart';
import '../config/scheme.dart';
import '../models/server_source.dart';
import '../providers/accent_provider.dart';
import '../providers/providers.dart';
import '../providers/source_provider.dart';
import '../services/api_client.dart';
import '../widgets/longbox_mark.dart';

/// Trims, adds `https://` when no scheme was typed, and drops trailing
/// slashes: `nas.local:8080/` → `https://nas.local:8080`.
String normalizeServerUrl(String input) {
  var url = input.trim();
  if (!url.contains('://')) url = 'https://$url';
  while (url.endsWith('/')) {
    url = url.substring(0, url.length - 1);
  }
  return url;
}

/// What to probe, in order. A typed scheme is taken as is; without one try
/// https, then plain http, which most LAN servers speak.
List<String> serverUrlCandidates(String input) {
  final url = normalizeServerUrl(input);
  if (input.trim().contains('://')) return [url];
  return [url, 'http://${url.substring('https://'.length)}'];
}

/// First launch with no server (every store install): ask for the server URL,
/// check it answers, then save it as the default source. `app.dart` swaps to
/// the shell once the active source has a URL, so this never pushes.
class OnboardingScreen extends ConsumerStatefulWidget {
  /// Returns the HTTP status of a normalized URL (null when unreachable).
  /// Defaults to [ApiClient.probeStatus].
  final Future<int?> Function(String url, Map<String, String> headers)? probe;

  const OnboardingScreen({super.key, this.probe});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _urlCtrl = TextEditingController();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _probing = false;
  String? _error;
  // Set once a candidate answered 401: the server needs a password.
  String? _authUrl;

  @override
  void dispose() {
    _urlCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<int?> _defaultProbe(String url, Map<String, String> headers) =>
      ApiClient(
        baseUrl: url,
        deviceId: ref.read(serverConfigProvider).deviceId,
        authHeaders: headers,
      ).probeStatus();

  bool _ok(int? s) => s != null && s >= 200 && s < 300;

  Future<void> _connect() async {
    final probe = widget.probe ?? _defaultProbe;
    final candidates =
        _authUrl != null ? [_authUrl!] : serverUrlCandidates(_urlCtrl.text);
    final user = _userCtrl.text;
    final pass = _passCtrl.text;
    final withAuth = _authUrl != null;
    final headers = withAuth
        ? ServerSource(
            id: '',
            name: '',
            type: SourceType.custom,
            baseUrl: '',
            authType: AuthType.basic,
            username: user,
            password: pass,
          ).authHeaders
        : const <String, String>{};
    setState(() {
      _probing = true;
      _error = null;
    });
    String? url;
    String? needsAuth;
    for (final c in candidates) {
      final status = await probe(c, headers);
      if (_ok(status)) {
        url = c;
        break;
      }
      if (status == 401) {
        needsAuth = c;
        break;
      }
    }
    if (!mounted) return;
    if (url != null) {
      // Credentials first: the shell mounts as soon as the URL lands, and its
      // first API calls must already carry auth.
      if (withAuth) {
        ref.read(sourceListProvider.notifier).updateDefaultBasicAuth(user, pass);
      }
      // Both, as Settings → Server URL does: covers and series detail build
      // URLs from ServerConfig, the API client from the source.
      await ref.read(serverConfigProvider).setServerUrl(url);
      if (!mounted) return;
      ref.read(sourceListProvider.notifier).updateDefaultUrl(url);
    } else if (needsAuth != null) {
      setState(() {
        _probing = false;
        _authUrl = needsAuth;
        _error =
            withAuth ? 'Wrong username or password' : 'This server needs a password';
      });
    } else {
      setState(() {
        _probing = false;
        _error = "Couldn't reach a server at ${candidates.first}. "
            'Check the address and that the server is running.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = ref.watch(accentProvider).value ?? AppTheme.accent;
    return Scaffold(
      backgroundColor: context.scheme.bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LongboxMark(size: 72, accent: accent),
                  const SizedBox(height: 20),
                  Text(appName,
                      style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 8),
                  Text('Connect to your comic server',
                      style: TextStyle(color: context.scheme.t2)),
                  const SizedBox(height: 28),
                  ValueListenableBuilder(
                    valueListenable: _urlCtrl,
                    builder: (context, value, _) => Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: _urlCtrl,
                          keyboardType: TextInputType.url,
                          autocorrect: false,
                          enableSuggestions: false,
                          textInputAction: TextInputAction.go,
                          onSubmitted: (_) =>
                              value.text.trim().isEmpty || _probing
                                  ? null
                                  : _connect(),
                          decoration: const InputDecoration(
                            labelText: 'Server address',
                            hintText: 'comics.example.com',
                          ),
                        ),
                        if (_authUrl != null) ...[
                          const SizedBox(height: 16),
                          TextField(
                            controller: _userCtrl,
                            autocorrect: false,
                            enableSuggestions: false,
                            autofillHints: const [AutofillHints.username],
                            decoration:
                                const InputDecoration(labelText: 'Username'),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _passCtrl,
                            obscureText: true,
                            autofillHints: const [AutofillHints.password],
                            onSubmitted: (_) => _probing ? null : _connect(),
                            decoration:
                                const InputDecoration(labelText: 'Password'),
                          ),
                        ],
                        const SizedBox(height: 16),
                        FilledButton(
                          style:
                              FilledButton.styleFrom(backgroundColor: accent),
                          onPressed: value.text.trim().isEmpty || _probing
                              ? null
                              : _connect,
                          child: _probing
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2))
                              : const Text('Connect'),
                        ),
                      ],
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(_error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: context.scheme.t2)),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
