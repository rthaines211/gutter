import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_theme.dart';
import '../config/scheme.dart';
import 'liquid_glass.dart';

const _kPrefKey = 'tap_zone_onboarding_v2_shown';

Future<bool> shouldShowTapZoneOnboarding() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_kPrefKey) != true;
}

Future<void> markTapZoneOnboardingShown() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_kPrefKey, true);
}

/// Page-turn regions per layout, normalized (0..1). Mirrors the geometry and
/// actions in lib/services/tap_zone_layout.dart's `_layouts` (no-op/menu
/// regions are omitted). 'left'/'right' flip with reading direction;
/// 'back'/'forward' don't. 'disabled' has none, so only the swipe-up line
/// shows for it.
const Map<String, List<(Rect, String)>> _hintZones = {
  'standard': [
    (Rect.fromLTRB(0, 0, 1 / 3, 1), 'left'),
    (Rect.fromLTRB(2 / 3, 0, 1, 1), 'right'),
  ],
  'edge': [
    (Rect.fromLTRB(0, 0, 0.25, 1), 'left'),
    (Rect.fromLTRB(0.55, 0, 1, 1), 'right'),
  ],
  'thumb': [
    (Rect.fromLTRB(0.6, 0, 1, 0.5), 'back'),
    (Rect.fromLTRB(0.6, 0.5, 1, 1), 'forward'),
  ],
  'disabled': [],
};

class TapZoneOnboarding extends StatefulWidget {
  const TapZoneOnboarding({
    super.key,
    required this.onDismiss,
    this.accent = AppTheme.accent,
    required this.layout,
    this.rtl = false,
    this.peek = false,
  });

  /// Brief look on reader open: no blur or swipe hint, taps pass through
  /// (the caller wraps it in IgnorePointer), and it fades itself out.
  final bool peek;

  final VoidCallback onDismiss;
  final Color accent;
  final String layout;

  /// Right-to-left reading: the left zone advances, so it says Next Page.
  final bool rtl;

  bool _isBack(String action) =>
      action == 'back' || action == (rtl ? 'right' : 'left');

  @override
  State<TapZoneOnboarding> createState() => _TapZoneOnboardingState();
}

class _TapZoneOnboardingState extends State<TapZoneOnboarding>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fadeIn;

  @override
  void initState() {
    super.initState();
    _fadeIn = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
    )..forward();
    if (widget.peek) _peekOut();
  }

  Future<void> _peekOut() async {
    await Future.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;
    await _fadeIn.reverse();
    if (mounted) widget.onDismiss();
  }

  @override
  void dispose() {
    _fadeIn.dispose();
    super.dispose();
  }

  void _handleTap() {
    markTapZoneOnboardingShown(); // fire-and-forget
    widget.onDismiss();
  }

  @override
  Widget build(BuildContext context) {
    final zones = _hintZones[widget.layout] ?? _hintZones['standard']!;

    return FadeTransition(
      opacity: _fadeIn,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerUp: (_) => _handleTap(),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Backdrop blur + dim
            if (!widget.peek)
              BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
                child: ColoredBox(color: context.scheme.scrim),
              ),

            // Back/forward zones for the current layout (none for 'disabled')
            LayoutBuilder(
              builder: (context, constraints) => Stack(
                children: [
                  for (final (rect, action) in zones)
                    Positioned(
                      left: rect.left * constraints.maxWidth,
                      top: rect.top * constraints.maxHeight,
                      width: rect.width * constraints.maxWidth,
                      height: rect.height * constraints.maxHeight,
                      child: _ZoneContent(
                        // The chevron points the way the tap moves the page.
                        icon: switch (action) {
                          'left' => Icons.chevron_left,
                          'right' => Icons.chevron_right,
                          'back' => Icons.expand_less,
                          _ => Icons.expand_more,
                        },
                        color: widget._isBack(action)
                            ? context.scheme.tx
                            : widget.accent,
                        label: widget._isBack(action)
                            ? 'Previous Page'
                            : 'Next Page',
                      ),
                    ),
                ],
              ),
            ),

            // Swipe-up hint pill
            if (!widget.peek)
              Positioned(
                bottom: 80,
                left: 0,
                right: 0,
                child: Center(
                  child: LiquidGlass(
                    radius: 999,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    child: Text(
                      'Swipe up for controls',
                      style: TextStyle(
                        color: context.scheme.tx,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ZoneContent extends StatelessWidget {
  const _ZoneContent({
    required this.icon,
    required this.color,
    required this.label,
  });

  final IconData icon;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    // Tinted fill + outline so the zone's extent reads, not just its center.
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 1),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.2),
                shape: BoxShape.circle,
                border: Border.all(
                  color: color.withValues(alpha: 0.5),
                  width: 1,
                ),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(height: 12),
            // On a glass chip so it reads over light pages (Sepia/white).
            LiquidGlass(
              radius: 999,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Text(
                label,
                style: TextStyle(
                  color: context.scheme.tx,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
