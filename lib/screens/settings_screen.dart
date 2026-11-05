import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/app_theme.dart';
import '../config/flavor.dart';
import '../config/comic_style.dart';
import '../config/scheme.dart';
import '../widgets/privacy_sheet.dart';
import '../widgets/longbox_mark.dart';
import '../widgets/reader_settings_form.dart' show sleepSettingsRows;
import '../providers/accent_provider.dart';
import '../providers/connectivity_provider.dart';
import '../providers/download_provider.dart';
import '../providers/grid_density_provider.dart';
import '../providers/providers.dart';
import '../providers/scan_status_provider.dart';
import '../providers/scheme_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/source_provider.dart';
import 'downloads_screen.dart';
import 'label_screen.dart';
import 'log_viewer_screen.dart';
import 'rename_templates_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  Color get accent => ref.watch(accentProvider).value ?? AppTheme.accent;

  void _refreshLibrary() {
    HapticFeedback.selectionClick();
    ref.read(scanStatusProvider.notifier).startScan();
  }

  void _toggleScheme(SchemeId current) {
    HapticFeedback.selectionClick();
    ref.read(schemeProvider.notifier).select(
        current == SchemeId.oledBlack ? SchemeId.sepiaPaper : SchemeId.oledBlack);
  }

  void _cycleGridDensity(int current) {
    HapticFeedback.selectionClick();
    ref.read(gridDensityProvider.notifier).select(current >= 4 ? 2 : current + 1);
  }

  void _push(Widget screen, String routeName) {
    Navigator.of(context).push(MaterialPageRoute(
      settings: RouteSettings(name: routeName),
      builder: (_) => screen,
    ));
  }

  Future<void> _editServerUrl(String current) async {
    final controller = TextEditingController(text: current);
    try {
      final result = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: ctx.scheme.s1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Server URL'),
          content: TextField(
            controller: controller,
            style: TextStyle(color: ctx.scheme.tx),
            decoration: InputDecoration(
              hintText: 'https://komga.example.com',
              hintStyle: TextStyle(color: ctx.scheme.t3),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Save')),
          ],
        ),
      );
      if (result != null && result.isNotEmpty) {
        await ref.read(serverConfigProvider).setServerUrl(result);
        ref.read(sourceListProvider.notifier).updateDefaultUrl(result);
        ref.read(connectivityProvider.notifier).check();
      }
    } finally {
      controller.dispose();
    }
  }

  Future<void> _editApiKey(String current) async {
    final controller = TextEditingController(text: current);
    try {
      final result = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: ctx.scheme.s1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('API Key'),
          content: TextField(
            controller: controller,
            autocorrect: false,
            enableSuggestions: false,
            style: TextStyle(color: ctx.scheme.tx),
            decoration: InputDecoration(
              hintText: 'register_secret from the server config',
              hintStyle: TextStyle(color: ctx.scheme.t3),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Save')),
          ],
        ),
      );
      if (result != null) {
        ref.read(sourceListProvider.notifier).updateDefaultApiKey(result.trim());
      }
    } finally {
      controller.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final serverConfig = ref.watch(serverConfigProvider);
    final currentPreset = _currentAccentPreset();
    final isOnline = ref.watch(connectivityProvider);
    final schemeId = ref.watch(schemeProvider);
    final density = ref.watch(gridDensityProvider);
    final readerSettings = ref.watch(settingsProvider).value;
    final apiKey = ref
            .watch(sourceListProvider)
            .where((s) => s.isDefault)
            .firstOrNull
            ?.apiKey ??
        '';

    return Scaffold(
      backgroundColor: context.scheme.bg,
      body: Stack(
        children: [
          // Ambient accent gradient
          Positioned(
            top: 0, left: 0, right: 0, height: 200,
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -1),
                    radius: 1.2,
                    colors: [accent.withValues(alpha: 0.15), Colors.transparent],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: ListView(
              padding: const EdgeInsets.only(bottom: 120),
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 4, 20, 20),
                  child: Text('Settings', style: AppTheme.titleLarge),
                ),

                // Appearance
                _Section(
                  icon: Icons.brightness_6_rounded,
                  iconColor: AppTheme.violet,
                  title: 'Appearance',
                  children: [
                    _NavRow(
                      label: 'Theme',
                      value: switch (schemeId) {
                        SchemeId.oledBlack => 'OLED Black',
                        SchemeId.sepiaPaper => 'Sepia Paper',
                      },
                      onTap: () => _toggleScheme(schemeId),
                    ),
                    _AccentRow(
                      label: 'Accent Color',
                      currentPreset: currentPreset,
                      accent: accent,
                      onSelect: (preset) {
                        ref.read(accentProvider.notifier).selectPreset(preset);
                      },
                    ),
                  ],
                ),

                // Library
                _Section(
                  icon: Icons.local_library_rounded,
                  iconColor: AppTheme.blue,
                  title: 'Library',
                  children: [
                    _NavRow(
                      label: 'Grid Density',
                      value: '$density columns',
                      onTap: () => _cycleGridDensity(density),
                    ),
                    _NavRow(
                      label: 'Rename Templates',
                      onTap: () => _push(
                          const RenameTemplatesScreen(), '/rename-templates'),
                    ),
                    if (!isStore) _NavRow(
                      label: 'Label pages',
                      onTap: () => _push(const LabelScreen(), 'label'),
                    ),
                  ],
                ),

                // Sleep: reader settings you set once, not per comic. Hidden
                // until reader settings load, so a save can't write defaults
                // over the rest of them.
                if (readerSettings != null)
                  _Section(
                    icon: Icons.bedtime_rounded,
                    iconColor: AppTheme.violet,
                    title: 'Sleep',
                    children: sleepSettingsRows(
                      settings: readerSettings,
                      onChanged: ref.read(settingsProvider.notifier).save,
                      accent: accent,
                    ),
                  ),

                // Storage
                _Section(
                  icon: Icons.layers_rounded,
                  iconColor: AppTheme.amber,
                  title: 'Storage',
                  children: [
                    _NavRow(
                      label: 'Downloaded Comics',
                      onTap: () =>
                          _push(const DownloadsScreen(), '/downloads'),
                    ),
                    _ActionRow(
                      label: 'Clear Image Cache',
                      color: AppTheme.amber,
                      onTap: () {
                        HapticFeedback.mediumImpact();
                        PaintingBinding.instance.imageCache.clear();
                        PaintingBinding.instance.imageCache.clearLiveImages();
                      },
                    ),
                    _ToggleRow(
                      label: 'Auto-delete After Reading',
                      sub: 'Remove downloaded files when finished',
                      value: ref.watch(autoCleanupDownloadsProvider),
                      onChanged: (v) =>
                          ref.read(autoCleanupDownloadsProvider.notifier).set(v),
                    ),
                    _ToggleRow(
                      label: 'Pretend I\'m Offline',
                      sub: 'Check what you can read before a trip',
                      value: ref.watch(simulateOfflineProvider),
                      onChanged: (v) =>
                          ref.read(simulateOfflineProvider.notifier).set(v),
                    ),
                  ],
                ),

                // Server
                _Section(
                  icon: Icons.public_rounded,
                  iconColor: AppTheme.green,
                  title: 'Server',
                  children: [
                    _NavRow(
                      label: 'Server URL',
                      value: serverConfig.serverUrl,
                      onTap: () => _editServerUrl(serverConfig.serverUrl),
                    ),
                    // The key registers push, which is personal-only.
                    if (!isStore) _NavRow(
                      label: 'API Key',
                      value: apiKey.isEmpty ? 'Not set' : 'Set',
                      onTap: () => _editApiKey(apiKey),
                    ),
                    _StatusRow(
                      label: 'Connection',
                      value: isOnline ? 'Online' : 'Offline',
                      color: isOnline ? AppTheme.green : context.scheme.t3,
                    ),
                    _NavRow(
                      label: 'Refresh Library',
                      onTap: _refreshLibrary,
                    ),
                  ],
                ),

                // About
                _Section(
                  icon: Icons.info_outline_rounded,
                  iconColor: context.scheme.t2,
                  title: 'About',
                  children: [
                    // Brand lockup: the mark beside the wordmark, with the
                    // tagline beneath.
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                      child: Row(
                        children: [
                          LongboxMark(
                            size: 38,
                            accent: accent,
                            background: const Color(0xFF1B1720),
                            radius: 9,
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(appName.toUpperCase(),
                                  style: AppTheme.displayTextStyle(
                                    ComicTokens.watch(ref, context, accent),
                                    fontSize: 22,
                                  ).copyWith(color: context.scheme.tx)),
                              const SizedBox(height: 2),
                              Text(
                                  isStore
                                      ? 'Your comics, your server.'
                                      : 'Your longbox, online.',
                                  style: context.monoCaption),
                            ],
                          ),
                        ],
                      ),
                    ),
                    _NavRow(
                      label: 'Privacy',
                      onTap: () => showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: context.scheme.s2,
                        builder: (_) => const PrivacySheet(),
                      ),
                    ),
                  ],
                ),

                // Diagnostics (personal only: the log names servers and paths)
                if (!isStore) Builder(builder: (context) {
                  return _Section(
                    icon: Icons.bug_report_outlined,
                    iconColor: context.scheme.t2,
                    title: 'Diagnostics',
                    children: [
                      _NavRow(
                        label: 'Connection Logs',
                        onTap: () =>
                            _push(const LogViewerScreen(), '/log-viewer'),
                      ),
                    ],
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _currentAccentPreset() {
    for (final entry in AppTheme.accentPresets.entries) {
      if (entry.value == accent) return entry.key;
    }
    return 'custom';
  }
}

class _Section extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final List<Widget> children;

  const _Section({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 0, 32, 8),
            child: Row(
              children: [
                Container(
                  width: 20, height: 20,
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: iconColor.withValues(alpha: 0.3), width: 0.5),
                  ),
                  child: Icon(icon, size: 11, color: iconColor),
                ),
                const SizedBox(width: 8),
                Text(title.toUpperCase(), style: context.sectionHeader.copyWith(
                  color: context.scheme.t3)),
              ],
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: context.scheme.s1,
              borderRadius: BorderRadius.circular(AppTheme.r18),
              border: Border.all(color: context.scheme.borderFaint, width: 0.5),
            ),
            child: Column(
              children: List.generate(children.length, (i) {
                return Column(
                  children: [
                    children[i],
                    if (i < children.length - 1)
                      Divider(height: 0.5, thickness: 0.5,
                        color: context.scheme.borderFaint, indent: 16),
                  ],
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavRow extends StatelessWidget {
  final String label;
  final String? value;
  final VoidCallback? onTap;

  const _NavRow({required this.label, this.value, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(
              fontSize: 14.5, fontWeight: FontWeight.w500, letterSpacing: -0.1))),
            if (value != null)
              // Tight so the right-aligned value hugs the chevron instead of
              // sitting at the start of its half of the row.
              Flexible(fit: FlexFit.tight, child: Text(value!, style: TextStyle(
                fontSize: 13.5, color: context.scheme.t3),
                maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.right)),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 12, color: context.scheme.t4),
          ],
        ),
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  final String label;
  final String? sub;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleRow({required this.label, this.sub, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(
                  fontSize: 14.5, fontWeight: FontWeight.w500, letterSpacing: -0.1)),
                if (sub != null)
                  Text(sub!, style: TextStyle(
                    fontSize: 12, color: context.scheme.t3, height: 1.4)),
              ],
            ),
          ),
          Switch.adaptive(value: value, onChanged: onChanged, activeThumbColor: AppTheme.green, activeTrackColor: AppTheme.green.withValues(alpha: 0.4)),
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatusRow({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(
            fontSize: 14.5, fontWeight: FontWeight.w500, letterSpacing: -0.1))),
          Container(
            width: 6, height: 6,
            decoration: BoxDecoration(
              color: color, shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 6)],
            ),
          ),
          const SizedBox(width: 6),
          Text(value, style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionRow({required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            Expanded(child: Text(label, style: TextStyle(
              fontSize: 14.5, fontWeight: FontWeight.w500, color: color, letterSpacing: -0.1))),
          ],
        ),
      ),
    );
  }
}

class _AccentRow extends StatelessWidget {
  final String label;
  final String currentPreset;
  final Color accent;
  final ValueChanged<String> onSelect;

  const _AccentRow({
    required this.label,
    required this.currentPreset,
    required this.accent,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(
            fontSize: 14.5, fontWeight: FontWeight.w500, letterSpacing: -0.1))),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: AppTheme.accentPresets.entries.map((e) {
              final isActive = e.key == currentPreset;
              return GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  onSelect(e.key);
                },
                child: Container(
                  width: 20, height: 20,
                  margin: const EdgeInsets.only(left: 4),
                  decoration: BoxDecoration(
                    color: e.value, shape: BoxShape.circle,
                    border: isActive ? Border.all(color: Scheme.onAccent(e.value), width: 2) : null,
                    boxShadow: isActive
                        ? [BoxShadow(color: e.value.withValues(alpha: 0.4), blurRadius: 6)]
                        : null,
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right, size: 12, color: context.scheme.t4),
        ],
      ),
    );
  }
}
