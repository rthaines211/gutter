import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/app_theme.dart';
import '../config/flavor.dart';
import '../config/platform.dart';
import '../config/scheme.dart';
import '../providers/accent_provider.dart';
import '../providers/providers.dart';
import '../providers/source_provider.dart';
import '../models/server_source.dart';
import '../widgets/local_import_button.dart';
import '../services/kavita_client.dart';
import '../widgets/longbox_mark.dart';
import '../config/server_url.dart';

export '../config/server_url.dart';

/// First launch with no server (every store install): ask for the server
/// type, URL and (Komga/Kavita) login, check it answers, then save it as the default
/// source. `app.dart` swaps to the shell once the active source has a URL, so
/// this never pushes.
///
/// With [onConnected] it is the Servers screen's edit/add form instead: it
/// gets an app bar, starts from [initial], and hands the probed server to
/// [onConnected] rather than saving it.
class OnboardingScreen extends ConsumerStatefulWidget {
  /// HTTP status from a candidate source (normalized URL, type, credentials),
  /// null when unreachable. Defaults to the source's client `probeStatus`.
  final Future<int?> Function(ServerSource candidate)? probe;

  /// Kavita's auth key for the candidate's username and password, null when
  /// refused. Defaults to [KavitaClient.login].
  final Future<String?> Function(ServerSource candidate)? kavitaLogin;

  /// The server being edited: prefills type, address and login.
  final ServerSource? initial;

  /// Edit/add mode: called with the server once it answers.
  final Future<void> Function(ServerSource found)? onConnected;

  const OnboardingScreen(
      {super.key, this.probe, this.kavitaLogin, this.initial, this.onConnected});

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
  void initState() {
    super.initState();
    final s = widget.initial;
    if (s == null) return;
    _type = s.type == SourceType.komga ||
            s.type == SourceType.kavita ||
            s.type == SourceType.opds
        ? s.type
        : SourceType.custom;
    _urlCtrl.text = s.address;
    _userCtrl.text = s.username ?? '';
    _passCtrl.text = s.password ?? '';
    _keyCtrl.text = s.apiKey ?? '';
    _useKey = _komga && s.authType == AuthType.apiKey;
    if (!_komga && s.authType == AuthType.basic) _authUrl = s.baseUrl;
  }

  @override
  void dispose() {
    for (final c in [_urlCtrl, _userCtrl, _passCtrl, _keyCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Komga or Kavita: a login form up front (vs the Gutter server's prompt
  /// on a 401).
  bool get _komga => _type != SourceType.custom;

  /// OPDS: the login is optional (many catalogs are open, Kavita's has its
  /// key in the address) and there is no API-key option.
  bool get _opds => _type == SourceType.opds;

  bool get _canConnect =>
      !_probing &&
      _urlCtrl.text.trim().isNotEmpty &&
      (!_komga ||
          _opds ||
          (_useKey
              ? _keyCtrl.text.trim().isNotEmpty
              : _userCtrl.text.trim().isNotEmpty && _passCtrl.text.isNotEmpty));

  ServerSource _candidate(String url) {
    if (!_komga && _authUrl == null) {
      // First try on a Gutter server: whatever auth the server being edited
      // (or the default source) already has, e.g. the personal build's
      // built-in key, so a server that accepts it connects unprompted.
      final ServerSource current =
          widget.initial ?? ref.read(activeSourceProvider);
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
    if (_opds) {
      // The origin is the source's address, so feed paths concatenate onto
      // it and the login goes to that origin only (OpdsClient).
      final u = Uri.parse(url);
      final user = _userCtrl.text.trim();
      return ServerSource(
        id: 'default',
        name: _type.label,
        type: _type,
        baseUrl: u.origin,
        catalogPath: '${u.path}${u.hasQuery ? '?${u.query}' : ''}',
        authType: user.isEmpty ? AuthType.none : AuthType.basic,
        username: user.isEmpty ? null : user,
        password: user.isEmpty ? null : _passCtrl.text,
        isDefault: true,
      );
    }
    final basic = !_komga || !_useKey;
    return ServerSource(
      id: 'default',
      name: _komga ? _type.label : 'My Server',
      type: _type,
      baseUrl: url,
      authType: basic ? AuthType.basic : AuthType.apiKey,
      username: basic ? _userCtrl.text.trim() : null,
      password: basic ? _passCtrl.text : null,
      apiKey: basic ? null : _keyCtrl.text.trim(),
      isDefault: true,
    );
  }

  Future<String?> _defaultKavitaLogin(ServerSource s) => KavitaClient(
          baseUrl: s.baseUrl, deviceId: ref.read(serverConfigProvider).deviceId)
      .login(s.username ?? '', s.password ?? '');

  /// Kavita has no basic auth: trade the login for the account's auth key,
  /// which is what gets saved.
  Future<ServerSource?> _withKavitaKey(ServerSource s) async {
    if (s.type != SourceType.kavita || s.authType != AuthType.basic) return s;
    final key = await (widget.kavitaLogin ?? _defaultKavitaLogin)(s);
    if (key == null) return null;
    return ServerSource(
      id: s.id,
      name: s.name,
      type: s.type,
      baseUrl: s.baseUrl,
      authType: AuthType.apiKey,
      apiKey: key,
      isDefault: s.isDefault,
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
      final source = await _withKavitaKey(_candidate(c));
      if (source == null) continue;
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
    if (found != null && widget.onConnected != null) {
      await widget.onConnected!(found);
      if (mounted) setState(() => _probing = false);
    } else if (found != null) {
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
        _error = _opds
            ? "Couldn't open an OPDS catalog at ${candidates.first}. Enter "
                "the OPDS catalog address from your server's settings, and "
                'your login if it has one.'
            : _komga
            ? "Couldn't sign in to ${_type.label} at ${candidates.first}. "
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
      appBar: widget.onConnected == null
          ? null
          : AppBar(
              backgroundColor: context.scheme.bg,
              title: Text(widget.initial == null ? 'Add server' : 'Edit server'),
            ),
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
                          value: SourceType.kavita, label: Text('Kavita')),
                      ButtonSegment(
                          value: SourceType.opds, label: Text('OPDS')),
                      ButtonSegment(
                          value: SourceType.custom,
                          label: Text('Gutter server')),
                    ],
                    selected: {_type},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) => setState(() {
                      _type = s.first;
                      if (_opds) _useKey = false;
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
                            hint: switch (_type) {
                              SourceType.komga => 'komga.example.com:25600',
                              SourceType.kavita => 'kavita.example.com:5000',
                              SourceType.opds =>
                                'comics.example.com/opds/v1.2/catalog',
                              _ => 'comics.example.com',
                            },
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
                              hint: _opds ? 'Optional' : null,
                              keyboard: TextInputType.emailAddress),
                          _field(_passCtrl, 'Password',
                              hint: _opds ? 'Optional' : null, obscure: true),
                        ],
                        if (!_komga && _authUrl != null) ...[
                          _field(_userCtrl, 'Username',
                              hint: 'Any name works for Gutter Server'),
                          _field(_passCtrl, 'Password', obscure: true),
                        ],
                        if (_komga && _useKey)
                          _field(_keyCtrl, 'API key', obscure: true),
                        if (_komga && !_opds)
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
                  // No server needed. iOS only in v1 (no Android picker).
                  if (widget.onConnected == null && !isAndroid) ...[
                    const SizedBox(height: 12),
                    const LocalImportButton(intoLocal: true),
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
