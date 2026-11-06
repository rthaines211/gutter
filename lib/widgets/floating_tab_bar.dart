import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/app_theme.dart';
import '../config/flavor.dart';
import '../config/scheme.dart';
import 'liquid_glass.dart';
import 'offline_dot.dart';

class FloatingTabBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final Color accent;
  final bool offline;
  final int reviewCount;

  const FloatingTabBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.accent = AppTheme.accent,
    this.offline = false,
    this.reviewCount = 0,
    this.serverTabs = true,
  });

  /// False hides Creators and Review (a source that isn't a Gutter server).
  final bool serverTabs;

  static const _tabs = [
    (icon: Icons.play_arrow_rounded, activeIcon: null, label: 'Read'),
    (icon: Icons.auto_stories_rounded, activeIcon: null, label: 'Library'),
    (icon: Icons.people_alt_outlined, activeIcon: Icons.people_alt, label: 'Creators'),
    (icon: Icons.fact_check_rounded, activeIcon: null, label: 'Review'),
    (icon: Icons.more_horiz_rounded, activeIcon: null, label: 'More'),
  ];

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 18,
      left: 16,
      right: 16,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          LiquidGlass(
            radius: AppTheme.r28,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              // Offline, Creators (2) and Review (3) need the server: hidden.
              children: [0, 1, 2, 3, 4]
                  .where((i) => !(offline || isStore || !serverTabs) || (i != 2 && i != 3))
                  .map((i) {
                final tab = _tabs[i];
                final active = i == currentIndex;
                return Expanded(
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      onTap(i);
                    },
                    behavior: HitTestBehavior.opaque,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutBack,
                      height: 48,
                      decoration: BoxDecoration(
                        color: active
                            ? accent.withValues(alpha: 0.18)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Badge(
                            isLabelVisible:
                                i == 3 && reviewCount > 0,
                            label: Text('$reviewCount'),
                            backgroundColor: accent,
                            child: Icon(
                              active && tab.activeIcon != null
                                  ? tab.activeIcon!
                                  : tab.icon,
                              size: 20,
                              color: active ? accent : context.scheme.t2,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            tab.label,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.1,
                              color: active ? accent : context.scheme.t2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          if (offline)
            const Positioned(
              top: -2,
              right: 8,
              child: OfflineDot(),
            ),
        ],
      ),
    );
  }
}
