import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/app_theme.dart';
import '../config/flavor.dart';
import '../config/scheme.dart';
import '../providers/accent_provider.dart';
import '../providers/providers.dart';
import '../providers/source_provider.dart';
import '../models/server_source.dart';
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

/// First launch with no server (every store install): ask for the server
/// type, URL and (Komga) login, check it answers, then save it as the default
/// source. `app.dart` swaps to the shell once the active source has a URL, so
/// this never pushes.
class OnboardingScreen extends ConsumerStatefulWidget {
  /// HTTP status from a candidate source (normalized URL, type, credentials),
  /// null when unreachable. Defaults to the source's client `probeStatus`.
  final Future<int?> Function(ServerSource candidate)? probe;

  const OnboardingScreen({super.key, this.probe});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _urlCtrl = TextEditingController();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _keyCtrl = TextEditingController();
  late final _fields = Listenable.merge([_urlCtrl, _userCtrl, _passCtrl, _keyCtrl]);
  var _type = SourceType.komga;
  bool _useKey = false;
  bool _probing = false;
  String? _error;
  // Gutter server only: set once a candidate answered 401, so the server
  // needs a password.
  String? _authUrl;

  @override
  void dispose() {
    for (final c in [_urlCtrl, _userCtrl, _passCtrl, _keyCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _komga => _type == SourceType.komga;

  bool get _canConnect =>
      !_probing &&
      _urlCtrl.text.trim().isNotEmpty &&
      (!_komga ||
          (_useKey
              ? _keyCtrl.text.trim().isNotEmpty
              : _userCtrl.text.trim().isNotEmpty && _passCtrl.text.isNotEmpty));

  ServerSource _candidate(String url) {
    if (!_komga && _authUrl == null) {
      // First try on a Gutter server: whatever auth the default source
      // already has (the personal build's built-in key), so a server that
      // accepts it connects unprompted.
      final current = ref.read(activeSourceProvider);
      return ServerSource(
        id: 'default',
        name: 'My Server',
        type: _type,
        baseUrl: url,
        authType: current.authType,
        username: current.username,
        password: current.password,
        apiKey: current.apiKey,
        isDefault: true,
      );
    }
    final basic = !_komga || !_useKey;
    return ServerSource(
      id: 'default',
      name: _komga ? 'Komga' : 'My Server',
      type: _type,
      baseUrl: url,
      authType: basic ? AuthType.basic : AuthType.apiKey,
      username: basic ? _userCtrl.text.trim() : null,
      password: basic ? _passCtrl.text : null,
      apiKey: basic ? null : _keyCtrl.text.trim(),
      isDefault: true,
    );
  }

  Future<int?> _defaultProbe(ServerSource source) =>
      clientFor(source, deviceId: ref.read(serverConfigProvider).deviceId)
          .probeStatus();

  bool _ok(int? s) => s != null && s >= 200 && s < 300;

  Future<void> _connect() async {
    // A login is never retried over plain http unless typed: a blocked 443
    // would otherwise send the password in the clear.
    final candidates = _authUrl != null
        ? [_authUrl!]
        : serverUrlCandidates(_urlCtrl.text).take(_komga ? 1 : 2).toList();
    final withAuth = _authUrl != null;
    setState(() {
      _probing = true;
      _error = null;
    });
    ServerSource? found;
    String? needsAuth;
    for (final c in candidates) {
      final source = _candidate(c);
      final status = await (widget.probe ?? _defaultProbe)(source);
      if (_ok(status)) {
        found = source;
        break;
      }
      if (!_komga && status == 401) {
        needsAuth = c;
        break;
      }
    }
    if (!mounted) return;
    if (found != null) {
      // Both, as Settings → Server URL does: covers and series detail build
      // URLs from ServerConfig, the API client from the source.
      await ref.read(serverConfigProvider).setServerUrl(found.baseUrl);
      if (!mounted) return;
      ref.read(sourceListProvider.notifier).setDefaultServer(found);
    } else if (needsAuth != null) {
      setState(() {
        _probing = false;
        _authUrl = needsAuth;
        _error = withAuth
            ? 'Wrong username or password'
            : 'This server needs a password';
      });
    } else {
      setState(() {
        _probing = false;
        _error = _komga
            ? "Couldn't sign in to Komga at ${candidates.first}. "
                'Check the address and your login.'
            : "Couldn't reach a server at ${candidates.first}. "
                'Check the address and that the server is running.';
      });
    }
  }

  Widget _field(TextEditingController c, String label,
          {String? hint,
          bool obscure = false,
          TextInputType? keyboard,
          ValueChanged<String>? onChanged}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          obscureText: obscure,
          keyboardType: keyboard,
          autocorrect: false,
          enableSuggestions: false,
          onChanged: onChanged,
          onSubmitted: (_) => _canConnect ? _connect() : null,
          decoration: InputDecoration(labelText: label, hintText: hint),
        ),
      );

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
                  SegmentedButton<SourceType>(
                    segments: const [
                      ButtonSegment(
                          value: SourceType.komga, label: Text('Komga')),
                      ButtonSegment(
                          value: SourceType.custom,
                          label: Text('Gutter server')),
                    ],
                    selected: {_type},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) => setState(() {
                      _type = s.first;
                      _error = null;
                      _authUrl = null;
                    }),
                  ),
                  const SizedBox(height: 20),
                  ListenableBuilder(
                    listenable: _fields,
                    builder: (context, _) => Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _field(_urlCtrl, 'Server address',
                            hint: _komga
                                ? 'komga.example.com:25600'
                                : 'comics.example.com',
                            keyboard: TextInputType.url,
                            // A new address starts over: drop the credential
                            // prompt and error left from the last one.
                            onChanged: (_) {
                              if (_authUrl != null || _error != null) {
                                setState(() {
                                  _authUrl = null;
                                  _error = null;
                                });
                              }
                            }),
                        if (_komga && !_useKey) ...[
                          _field(_userCtrl, 'Username',
                              keyboard: TextInputType.emailAddress),
                          _field(_passCtrl, 'Password', obscure: true),
                        ],
                        if (!_komga && _authUrl != null) ...[
                          _field(_userCtrl, 'Username',
                              hint: 'Any name works for Gutter Server'),
                          _field(_passCtrl, 'Password', obscure: true),
                        ],
                        if (_komga && _useKey)
                          _field(_keyCtrl, 'API key', obscure: true),
                        if (_komga)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton(
                              onPressed: () =>
                                  setState(() => _useKey = !_useKey),
                              child: Text(_useKey
                                  ? 'Use username and password'
                                  : 'Use an API key'),
                            ),
                          ),
                        const SizedBox(height: 4),
                        FilledButton(
                          style:
                              FilledButton.styleFrom(backgroundColor: accent),
                          onPressed: _canConnect ? _connect : null,
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
