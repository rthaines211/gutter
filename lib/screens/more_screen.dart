import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/app_theme.dart';
import '../config/flavor.dart';
import '../config/scheme.dart';
import '../providers/accent_provider.dart';
import '../providers/connectivity_provider.dart';
import '../providers/download_provider.dart';
import '../providers/providers.dart';
import 'arcs_screen.dart';
import 'downloads_screen.dart';
import 'queues_screen.dart';
import 'remote_screen.dart';
import 'stats_screen.dart';
import 'settings_screen.dart';

class MoreScreen extends ConsumerStatefulWidget {
  const MoreScreen({super.key});

  @override
  ConsumerState<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends ConsumerState<MoreScreen> {
  bool? _isOnline;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _checkConnection();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _checkConnection(),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkConnection() async {
    final client = ref.read(apiClientProvider);
    final online = await client.checkConnection();
    if (mounted) setState(() => _isOnline = online);
  }

  @override
  Widget build(BuildContext context) {
    final accent = ref.watch(accentProvider).value ?? AppTheme.accent;
    // Remote and Stats need the server: hidden offline.
    final online = ref.watch(connectivityProvider);
    final downloadState = ref.watch(downloadStateProvider);
    final queueCount = downloadState.value?.queue.length ?? 0;
    final completedCount = downloadState.value?.completed.length ?? 0;
    final totalDownloads = queueCount + completedCount;

    return Scaffold(
      backgroundColor: context.scheme.bg,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 120),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 20),
              child: Text('More', style: AppTheme.titleLarge),
            ),

            // Status tiles
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              child: Row(
                children: [
                  Expanded(
                    child: _StatusTile(
                      label: 'Downloads',
                      value: '$totalDownloads',
                      sub: queueCount > 0 ? '$queueCount queued' : null,
                      icon: Icons.download_rounded,
                      color: accent,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _StatusTile(
                      label: 'Server',
                      value: _isOnline == true ? 'Online' : (_isOnline == false ? 'Offline' : '...'),
                      icon: Icons.public_rounded,
                      color: _isOnline == true ? AppTheme.green : context.scheme.t3,
                      pulse: _isOnline == true,
                    ),
                  ),
                ],
              ),
            ),

            _MoreGroup(
              header: 'Content',
              rows: [
                _MoreRow(
                  icon: Icons.download_rounded,
                  iconColor: accent,
                  label: 'Downloads',
                  sub: 'Offline reading',
                  value: '$totalDownloads series',
                  onTap: () => _push(context, const DownloadsScreen(), '/downloads'),
                ),
                _MoreRow(
                  icon: Icons.playlist_play_rounded,
                  iconColor: AppTheme.violet,
                  label: 'Queues',
                  sub: 'Plan your next reads',
                  onTap: () => _push(context, const QueuesScreen(), '/queues'),
                ),
                if (online && !isStore) _MoreRow(
                  icon: Icons.settings_remote_rounded,
                  iconColor: AppTheme.blue,
                  label: 'Remote',
                  sub: 'Control the iPad reader',
                  onTap: () => _push(context, const RemoteScreen(), '/remote'),
                ),
                _MoreRow(
                  icon: Icons.account_tree_rounded,
                  iconColor: AppTheme.violet,
                  label: 'Story Arcs',
                  sub: 'Read collected storylines in order',
                  onTap: () => _push(context, const ArcsScreen(), '/arcs'),
                ),
                _MoreRow(
                  icon: Icons.public_rounded,
                  iconColor: AppTheme.green,
                  label: 'Sources',
                  value: '1 connected',
                  onTap: () => _push(context, const SettingsScreen(), '/settings'),
                ),
              ],
            ),

            _MoreGroup(
              header: 'Insights',
              rows: [
                if (online) _MoreRow(
                  icon: Icons.bar_chart_rounded,
                  iconColor: AppTheme.violet,
                  label: 'Reading Stats',
                  sub: 'Streaks, sessions, genres',
                  onTap: () => _push(context, const StatsScreen(), '/stats'),
                ),
                _MoreRow(
                  icon: Icons.bookmark_rounded,
                  iconColor: AppTheme.amber,
                  label: 'Bookmarks',
                  onTap: () {},
                ),
                _MoreRow(
                  icon: Icons.access_time_rounded,
                  iconColor: context.scheme.t2,
                  label: 'Recently Read',
                  onTap: () {},
                ),
              ],
            ),

            _MoreGroup(
              header: 'Account',
              rows: [
                _MoreRow(
                  icon: Icons.settings_rounded,
                  iconColor: context.scheme.t2,
                  label: 'Settings',
                  onTap: () => _push(context, const SettingsScreen(), '/settings'),
                ),
                _MoreRow(
                  icon: Icons.info_outline_rounded,
                  iconColor: context.scheme.t2,
                  label: 'About LCS',
                  value: 'v2.0',
                  onTap: () {},
                ),
                _MoreRow(
                  icon: Icons.favorite_rounded,
                  iconColor: accent,
                  label: 'Rate LCS',
                  onTap: () {},
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _push(BuildContext context, Widget screen, String routeName) {
    HapticFeedback.selectionClick();
    Navigator.push(context, MaterialPageRoute(
      settings: RouteSettings(name: routeName),
      builder: (_) => screen,
    ));
  }
}

class _StatusTile extends StatelessWidget {
  final String label;
  final String value;
  final String? sub;
  final IconData icon;
  final Color color;
  final bool pulse;

  const _StatusTile({
    required this.label,
    required this.value,
    this.sub,
    required this.icon,
    required this.color,
    this.pulse = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.scheme.s1,
        borderRadius: BorderRadius.circular(AppTheme.r18),
        border: Border.all(
          color: context.scheme.borderFaint,
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 26, height: 26,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Icon(icon, size: 13, color: color),
              ),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(
                fontSize: 12, color: context.scheme.t3, fontWeight: FontWeight.w600)),
              if (pulse) ...[
                const SizedBox(width: 6),
                Container(
                  width: 6, height: 6,
                  decoration: BoxDecoration(
                    color: color, shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 6)],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Text(value, style: const TextStyle(
            fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.5, height: 1)),
          if (sub != null) ...[
            const SizedBox(height: 2),
            Text(sub!, style: context.monoCaption),
          ],
        ],
      ),
    );
  }
}

class _MoreGroup extends StatelessWidget {
  final String header;
  final List<_MoreRow> rows;

  const _MoreGroup({required this.header, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 0, 32, 6),
            child: Text(header.toUpperCase(), style: context.sectionHeader),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: context.scheme.s1,
              borderRadius: BorderRadius.circular(AppTheme.r18),
              border: Border.all(
                color: context.scheme.borderFaint,
                width: 0.5,
              ),
            ),
            child: Column(
              children: List.generate(rows.length, (i) {
                return Column(
                  children: [
                    rows[i],
                    if (i < rows.length - 1)
                      Divider(height: 0.5, thickness: 0.5,
                        color: context.scheme.hair, indent: 54),
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

class _MoreRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String? sub;
  final String? value;
  final VoidCallback onTap;

  const _MoreRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    this.sub,
    this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 30, height: 30,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 15, color: iconColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w500, letterSpacing: -0.15)),
                  if (sub != null)
                    Text(sub!, style: TextStyle(
                      fontSize: 11, color: context.scheme.t3, height: 1.4)),
                ],
              ),
            ),
            if (value != null)
              Text(value!, style: TextStyle(fontSize: 13, color: context.scheme.t3)),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 12, color: context.scheme.t4),
          ],
        ),
      ),
    );
  }
}
