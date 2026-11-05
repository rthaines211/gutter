import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/app_theme.dart';
import '../config/flavor.dart';
import '../config/scheme.dart';
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

/// First launch with no server (every store install): ask for the server URL,
/// check it answers, then save it as the default source. `app.dart` swaps to
/// the shell once the active source has a URL, so this never pushes.
class OnboardingScreen extends ConsumerStatefulWidget {
  /// Checks a normalized URL reaches a server. Defaults to
  /// [ApiClient.checkConnection].
  final Future<bool> Function(String url)? probe;

  const OnboardingScreen({super.key, this.probe});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _urlCtrl = TextEditingController();
  bool _probing = false;
  String? _error;

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<bool> _defaultProbe(String url) => ApiClient(
        baseUrl: url,
        deviceId: ref.read(serverConfigProvider).deviceId,
      ).checkConnection();

  Future<void> _connect() async {
    final url = normalizeServerUrl(_urlCtrl.text);
    setState(() {
      _probing = true;
      _error = null;
    });
    final ok = await (widget.probe ?? _defaultProbe)(url);
    if (!mounted) return;
    if (ok) {
      // Both, as Settings → Server URL does: covers and series detail build
      // URLs from ServerConfig, the API client from the source.
      await ref.read(serverConfigProvider).setServerUrl(url);
      if (!mounted) return;
      ref.read(sourceListProvider.notifier).updateDefaultUrl(url);
    } else {
      setState(() {
        _probing = false;
        _error = "Couldn't reach a server at $url. "
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
