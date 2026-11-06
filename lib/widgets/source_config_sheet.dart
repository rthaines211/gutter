// lib/widgets/source_config_sheet.dart
import 'package:flutter/material.dart';
import '../providers/providers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/app_theme.dart';
import '../config/scheme.dart';
import '../models/server_source.dart';
import '../providers/source_provider.dart';
import '../services/opds_client.dart';

class SourceConfigSheet extends ConsumerStatefulWidget {
  final ServerSource? existing;
  final Color accent;

  const SourceConfigSheet({super.key, this.existing, this.accent = AppTheme.accent});

  @override
  ConsumerState<SourceConfigSheet> createState() => _SourceConfigSheetState();
}

class _SourceConfigSheetState extends ConsumerState<SourceConfigSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _urlCtrl;
  late final TextEditingController _userCtrl;
  late final TextEditingController _passCtrl;
  late final TextEditingController _keyCtrl;
  late AuthType _authType;
  late SourceType _type;
  bool _testing = false;
  String? _testResult;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.existing?.name ?? '');
    _urlCtrl = TextEditingController(text: widget.existing?.baseUrl ?? '');
    _userCtrl = TextEditingController(text: widget.existing?.username ?? '');
    _passCtrl = TextEditingController(text: widget.existing?.password ?? '');
    _keyCtrl = TextEditingController(text: widget.existing?.apiKey ?? '');
    _authType = widget.existing?.authType ?? AuthType.none;
    _type = widget.existing?.type ?? SourceType.komga;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _urlCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    _keyCtrl.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });

    try {
      final source = _buildSource();
      if (_type == SourceType.komga) {
        final ok = await clientFor(source,
                deviceId: ref.read(serverConfigProvider).deviceId)
            .checkConnection();
        setState(() {
          _testing = false;
          _testResult = ok ? 'Connected' : 'Failed: check the address and login';
        });
        return;
      }
      final client = OPDSClient(source: source);
      final feed = await client.fetchRoot();
      setState(() {
        _testing = false;
        _testResult = 'Connected — "${feed.title}" (${feed.entries.length} entries)';
      });
    } catch (e) {
      setState(() {
        _testing = false;
        _testResult = 'Failed: couldn\'t reach the server';
      });
    }
  }

  ServerSource _buildSource() {
    return ServerSource(
      id: widget.existing?.id ?? generateSourceId(),
      name: _nameCtrl.text.trim().isNotEmpty
          ? _nameCtrl.text.trim()
          : _type == SourceType.komga ? 'Komga' : 'OPDS Source',
      type: _type,
      baseUrl: _urlCtrl.text.trim(),
      authType: _authType,
      username: _authType == AuthType.basic ? _userCtrl.text : null,
      password: _authType == AuthType.basic ? _passCtrl.text : null,
      apiKey: _authType == AuthType.apiKey ? _keyCtrl.text : null,
    );
  }

  void _save() {
    if (_urlCtrl.text.trim().isEmpty) return;

    final source = _buildSource();
    if (_isEditing) {
      ref.read(sourceListProvider.notifier).edit(widget.existing!.id, source);
    } else {
      ref.read(sourceListProvider.notifier).add(source);
      // Auto-switch to the new source
      ref.read(activeSourceIdProvider.notifier).select(source.id);
    }
    HapticFeedback.mediumImpact();
    Navigator.pop(context);
  }

  void _delete() {
    final id = widget.existing!.id;
    // Switch to default if deleting the active source
    final activeId = ref.read(activeSourceIdProvider);
    if (activeId == id) {
      ref.read(activeSourceIdProvider.notifier).select('default');
    }
    ref.read(sourceListProvider.notifier).remove(id);
    HapticFeedback.mediumImpact();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 40,
      ),
      decoration: BoxDecoration(
        color: context.scheme.s2,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: context.scheme.hairStrong,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _isEditing ? 'Edit Server' : 'Add Server',
                style: TextStyle(
                  color: context.scheme.tx,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 20),
              if (!_isEditing) ...[
                SegmentedButton<SourceType>(
                  segments: const [
                    ButtonSegment(value: SourceType.komga, label: Text('Komga')),
                    ButtonSegment(value: SourceType.opds, label: Text('OPDS')),
                  ],
                  selected: {_type},
                  showSelectedIcon: false,
                  onSelectionChanged: (v) => setState(() => _type = v.first),
                ),
                const SizedBox(height: 14),
              ],
              _buildField(context, 'Name', _nameCtrl,
                  _type == SourceType.komga ? 'Home Komga' : 'My Kavita Server'),
              const SizedBox(height: 14),
              _type == SourceType.komga
                  ? _buildField(context, 'Server URL', _urlCtrl,
                      'https://komga.local:25600')
                  : _buildField(context, 'Catalog URL', _urlCtrl,
                      'https://kavita.local/api/opds/abc'),
              const SizedBox(height: 14),
              // Auth type selector
              Text('Authentication',
                  style: TextStyle(
                      color: context.scheme.t2,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Row(
                children: AuthType.values.map((t) {
                  final active = t == _authType;
                  final label = switch (t) {
                    AuthType.none => 'None',
                    AuthType.basic => 'Basic',
                    AuthType.apiKey => 'API Key',
                  };
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () => setState(() => _authType = t),
                      child: Container(
                        height: 34,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: active
                              ? widget.accent.withValues(alpha: 0.2)
                              : context.scheme.s1,
                          borderRadius: BorderRadius.circular(17),
                          border: Border.all(
                            color: active
                                ? widget.accent.withValues(alpha: 0.4)
                                : context.scheme.borderFaint,
                            width: active ? 1 : 0.5,
                          ),
                        ),
                        child: Center(
                          child: Text(label,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: active
                                    ? widget.accent
                                    : context.scheme.t2,
                              )),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              if (_authType == AuthType.basic) ...[
                const SizedBox(height: 14),
                _buildField(context, 'Username', _userCtrl, 'admin'),
                const SizedBox(height: 14),
                _buildField(context, 'Password', _passCtrl, '', obscure: true),
              ],
              if (_authType == AuthType.apiKey) ...[
                const SizedBox(height: 14),
                _buildField(context, 'API Key', _keyCtrl, 'sk-...'),
              ],
              const SizedBox(height: 20),
              // Test connection
              GestureDetector(
                onTap: _testing ? null : _testConnection,
                child: Container(
                  height: 44,
                  decoration: BoxDecoration(
                    color: context.scheme.s1,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: context.scheme.borderFaint,
                      width: 0.5,
                    ),
                  ),
                  child: Center(
                    child: _testing
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: widget.accent,
                            ),
                          )
                        : Text('Test Connection',
                            style: TextStyle(
                              color: widget.accent,
                              fontWeight: FontWeight.w600,
                            )),
                  ),
                ),
              ),
              if (_testResult != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _testResult!,
                    style: TextStyle(
                      fontSize: 12,
                      color: _testResult!.startsWith('Connected')
                          ? AppTheme.green
                          : Colors.red[400],
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              // Save button
              GestureDetector(
                onTap: _save,
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: widget.accent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      _isEditing ? 'Save Changes' : 'Add Source',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ),
              if (_isEditing) ...[
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: _delete,
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                    ),
                    child: Center(
                      child: Text('Delete Source',
                          style: TextStyle(
                            color: Colors.red[400],
                            fontWeight: FontWeight.w600,
                          )),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildField(
    BuildContext context,
    String label,
    TextEditingController controller,
    String hint, {
    bool obscure = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                color: context.scheme.t2,
                fontSize: 12,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Container(
          height: 44,
          decoration: BoxDecoration(
            color: context.scheme.s1,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: context.scheme.borderFaint,
              width: 0.5,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: TextField(
              controller: controller,
              obscureText: obscure,
              style: TextStyle(color: context.scheme.tx, fontSize: 14),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(color: context.scheme.t4),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
