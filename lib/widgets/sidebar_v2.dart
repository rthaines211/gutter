import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/app_theme.dart';
import '../config/scheme.dart';
import '../providers/collection_provider.dart';
import '../providers/connectivity_provider.dart';
import '../providers/library_provider.dart';
import '../providers/navigation_provider.dart';
import '../providers/providers.dart';
import '../providers/smart_filter_provider.dart';
import 'offline_dot.dart';

class SidebarV2 extends ConsumerStatefulWidget {
  const SidebarV2({super.key});

  @override
  ConsumerState<SidebarV2> createState() => _SidebarV2State();
}

class _SidebarV2State extends ConsumerState<SidebarV2> {
  @override
  Widget build(BuildContext context) {
    final current = ref.watch(navigationProvider);
    final collections = ref.watch(collectionsProvider);
    final smartFilters = ref.watch(smartFilterListProvider);
    final serverConfig = ref.watch(serverConfigProvider);
    final isOnline = ref.watch(connectivityProvider);

    return Container(
      width: 232,
      color: context.scheme.bgRaised,
      child: Column(
        children: [
          SizedBox(height: MediaQuery.of(context).padding.top + 8),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppTheme.accent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.auto_stories_rounded, size: 18, color: Scheme.onAccent(AppTheme.accent)),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('LCS', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('COMIC SERVER', style: context.monoCaption),
                        if (!isOnline) ...[
                          const SizedBox(width: 6),
                          const OfflineDot(),
                        ],
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              children: [
                _NavRow(icon: Icons.play_arrow_rounded, label: 'Read', active: current == NavDestination.read, onTap: () => _navigate(NavDestination.read)),
                _NavRow(icon: Icons.auto_stories_rounded, label: 'Library', active: current == NavDestination.library, onTap: () => _navigate(NavDestination.library)),
                _NavRow(icon: Icons.people_alt_outlined, label: 'Creators', active: current == NavDestination.creators, onTap: () => _navigate(NavDestination.creators)),
                _NavRow(icon: Icons.download_rounded, label: 'Downloads', active: current == NavDestination.downloads, onTap: () => _navigate(NavDestination.downloads)),
                _NavRow(icon: Icons.playlist_play_rounded, label: 'Queues', active: current == NavDestination.queues, onTap: () => _navigate(NavDestination.queues)),
                _NavRow(icon: Icons.account_tree_rounded, label: 'Arcs', active: current == NavDestination.arcs, onTap: () => _navigate(NavDestination.arcs)),
                _NavRow(icon: Icons.bar_chart_rounded, label: 'Stats', active: current == NavDestination.stats, onTap: () => _navigate(NavDestination.stats)),
                const SizedBox(height: 16),
                _GroupHeader(label: 'Smart Filters'),
                smartFilters.when(
                  loading: () => const SizedBox.shrink(),
                  error: (_, _) => const SizedBox.shrink(),
                  data: (filters) => Column(children: filters.map((f) => _FilterRow(
                    label: f.name,
                    dotColor: _parseColor(f.color),
                    onTap: () {
                      HapticFeedback.selectionClick();
                      ref.read(navigationProvider.notifier).go(NavDestination.library);
                      ref.read(librarySmartFilterProvider.notifier).select(f.id);
                    },
                  )).toList()),
                ),
                const SizedBox(height: 16),
                _GroupHeader(label: 'Collections'),
                collections.when(
                  loading: () => const SizedBox.shrink(),
                  error: (_, _) => const SizedBox.shrink(),
                  data: (cols) => Column(children: cols.map((c) => _FilterRow(
                    label: c.name,
                    dotColor: _parseColor(c.color),
                    onTap: () {
                      HapticFeedback.selectionClick();
                      ref.read(navigationProvider.notifier).go(NavDestination.library);
                      ref.read(activeCollectionProvider.notifier).select(c.id);
                      ref.read(librarySmartFilterProvider.notifier).clear();
                    },
                  )).toList()),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: context.scheme.hair, width: 0.5))),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Container(
                    width: 8, height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isOnline ? AppTheme.green : const Color(0xFFFF453A),
                      boxShadow: [BoxShadow(color: (isOnline ? AppTheme.green : const Color(0xFFFF453A)).withValues(alpha: 0.4), blurRadius: 6)],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_hostname(serverConfig.serverUrl), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text(isOnline ? 'Online' : 'Offline', style: TextStyle(fontSize: 10, color: context.scheme.t3)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.settings_rounded, size: 18, color: context.scheme.t3),
                    onPressed: () => _navigate(NavDestination.settings),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _navigate(NavDestination dest) {
    HapticFeedback.selectionClick();
    ref.read(navigationProvider.notifier).go(dest);
  }

  static String _hostname(String url) {
    try { return Uri.parse(url).host; } catch (_) { return url; }
  }

  static Color _parseColor(String hex) {
    final cleaned = hex.replaceFirst('#', '');
    if (cleaned.length == 6) {
      final value = int.tryParse(cleaned, radix: 16);
      if (value != null) return Color(0xFF000000 | value);
    }
    return AppTheme.accent;
  }
}

class _NavRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _NavRow({required this.icon, required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 34,
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(color: active ? AppTheme.accent.withValues(alpha: 0.22) : Colors.transparent, borderRadius: BorderRadius.circular(8)),
        child: Row(children: [
          Icon(icon, size: 16, color: active ? AppTheme.accent : context.scheme.t2),
          const SizedBox(width: 10),
          Text(label, style: TextStyle(fontSize: 13, fontWeight: active ? FontWeight.w600 : FontWeight.w500, color: active ? AppTheme.accent : context.scheme.t2)),
        ]),
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  final String label;
  const _GroupHeader({required this.label});
  @override
  Widget build(BuildContext context) {
    return Padding(padding: const EdgeInsets.fromLTRB(10, 0, 10, 4), child: Text(label.toUpperCase(), style: context.sectionHeader.copyWith(fontSize: 10)));
  }
}

class _FilterRow extends StatelessWidget {
  final String label;
  final Color dotColor;
  final VoidCallback? onTap;
  const _FilterRow({required this.label, required this.dotColor, this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        child: SizedBox(height: 28, child: Row(children: [
          const SizedBox(width: 6),
          Container(width: 8, height: 8, decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle)),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: context.scheme.t2), maxLines: 1, overflow: TextOverflow.ellipsis)),
        ])),
      ),
    );
  }
}
