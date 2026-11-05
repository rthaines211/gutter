import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/app_theme.dart';
import '../config/flavor.dart';
import '../config/scheme.dart';
import '../providers/connectivity_provider.dart';
import '../providers/navigation_provider.dart';
import '../providers/review_provider.dart';
import 'longbox_mark.dart';

/// 76pt-wide iPad navigation rail — the tablet shell's default navigation.
///
/// It replaced the 236pt `SidebarV2`, which still exists in
/// `lib/widgets/sidebar_v2.dart` as a supported-but-unreachable nav mode:
/// the design specifies three (rail / sidebar / bottom tabs) and there is no
/// picker yet. To switch back, import it in `app_shell.dart` and swap the
/// `IconRail(...)` call in `_buildTablet`.
/// nav surface — see `app_shell.dart`. `SidebarV2` stays in the tree as a
/// supported (currently unpicked) nav mode; this is a sibling, not a
/// deletion of it.
class IconRail extends ConsumerWidget {
  final Color accent;

  const IconRail({super.key, this.accent = AppTheme.accent});

  static const _destinations = [
    (dest: NavDestination.read, icon: Icons.play_arrow_rounded, label: 'Read'),
    (dest: NavDestination.library, icon: Icons.auto_stories_rounded, label: 'Library'),
    (dest: NavDestination.creators, icon: Icons.people_alt_outlined, label: 'Creators'),
    (dest: NavDestination.review, icon: Icons.fact_check_rounded, label: 'Review'),
    (dest: NavDestination.downloads, icon: Icons.download_rounded, label: 'Downloads'),
    (dest: NavDestination.queues, icon: Icons.playlist_play_rounded, label: 'Queues'),
    (dest: NavDestination.arcs, icon: Icons.account_tree_rounded, label: 'Arcs'),
    (dest: NavDestination.stats, icon: Icons.bar_chart_rounded, label: 'Stats'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(navigationProvider);
    final reviewCount = isStore ? 0 : ref.watch(reviewCountProvider);
    final offline = !ref.watch(connectivityProvider);

    return Container(
      width: 76,
      color: context.scheme.bgRaised,
      child: Column(
        children: [
          SizedBox(height: MediaQuery.of(context).padding.top + 12),
          // The Longbox mark, on its Ink tile — the same geometry that
          // generates the app icon, so the two cannot drift.
          LongboxMark(
            size: 32,
            accent: accent,
            background: const Color(0xFF1B1720),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 4),
              children: [
                for (final d in _destinations)
                  if ((!offline || !onlineOnlyDestinations.contains(d.dest)) &&
                      !(isStore && storeHiddenDestinations.contains(d.dest)))
                  _RailTile(
                    icon: d.icon,
                    label: d.label,
                    active: current == d.dest,
                    accent: accent,
                    badge: d.dest == NavDestination.review ? reviewCount : 0,
                    onTap: () => _navigate(ref, d.dest),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SafeArea(
              top: false,
              child: _RailTile(
                icon: Icons.settings_rounded,
                label: 'Settings',
                active: current == NavDestination.settings,
                accent: accent,
                onTap: () => _navigate(ref, NavDestination.settings),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _navigate(WidgetRef ref, NavDestination dest) {
    HapticFeedback.selectionClick();
    ref.read(navigationProvider.notifier).go(dest);
  }
}

class _RailTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final Color accent;
  final VoidCallback onTap;
  final int badge;

  const _RailTile({
    required this.icon,
    required this.label,
    required this.active,
    required this.accent,
    required this.onTap,
    this.badge = 0,
  });

  @override
  Widget build(BuildContext context) {
    // "acs" fill: accent at 16% for the active tile. Distinct from
    // AppTheme.accentSoft (14%) — see issue_list_view.dart for precedent.
    final color = active ? accent : context.scheme.t2;

    return Center(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 58,
          height: 54,
          margin: const EdgeInsets.symmetric(vertical: 3),
          decoration: BoxDecoration(
            color: active ? accent.withValues(alpha: 0.16) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Badge(
                isLabelVisible: badge > 0,
                label: Text('$badge'),
                backgroundColor: accent,
                child: Icon(icon, size: 22, color: color),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                  color: color,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
