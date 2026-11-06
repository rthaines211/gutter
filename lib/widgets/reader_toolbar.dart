// lib/widgets/reader_toolbar.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/app_theme.dart';
import '../config/comic_style.dart';
import '../config/layout_breakpoint.dart';
import '../config/reading_estimate.dart';
import '../config/scheme.dart';
import '../services/sleep_timer.dart';
import 'claude_panel.dart';
import 'liquid_glass.dart';
import 'reader_more_menu.dart' show MoreItem;

/// Slim glass top bar: back, title + sub-line, moon, bookmark, Aa, more.
///
/// With [rail] (iPad) the same controls stack in a vertical rail on one
/// edge and the title becomes a tag in the opposite top corner; place it with
/// `Positioned.fill` (the empty space between them lets taps through).
class ReaderTopBar extends ConsumerWidget {
  final String title;

  /// Issue title or current chapter; shown uppercased before the time left.
  final String? subtitleLead;

  /// Pages after the current one; the time left comes from [formatMinutesLeft].
  final int pagesLeft;
  final bool isBookmarked;

  /// Whether the Aa panel / more menu is showing, so its button lights up.
  final bool isSettingsOpen;
  final bool isMoreOpen;
  final VoidCallback onClose;
  final VoidCallback onBookmark;
  final VoidCallback onSettings;
  final VoidCallback onMore;

  /// When set, these replace the More button, one bar button each.
  final List<MoreItem>? inlineMore;
  final VoidCallback? onTitleTap;

  /// Sleep-timer time left (null = off), re-read while mounted. The moon is
  /// hidden when [onSleepTimer] is null.
  final Duration? Function()? sleepRemaining;
  final VoidCallback? onSleepTimer;

  /// Claude panel state; the button shows on the rail only, when
  /// [onClaude] is set.
  final ClaudePanelMode claudeMode;
  final VoidCallback? onClaude;
  final Color accent;
  final bool rail;

  /// Rail on the left edge (title tag then goes top-right).
  final bool railOnLeft;

  const ReaderTopBar({
    super.key,
    required this.title,
    this.subtitleLead,
    required this.pagesLeft,
    required this.isBookmarked,
    required this.isSettingsOpen,
    required this.isMoreOpen,
    required this.onClose,
    required this.onBookmark,
    required this.onSettings,
    required this.onMore,
    this.inlineMore,
    this.onTitleTap,
    this.sleepRemaining,
    this.onSleepTimer,
    this.claudeMode = ClaudePanelMode.off,
    this.onClaude,
    this.accent = AppTheme.accent,
    this.rail = false,
    this.railOnLeft = false,
  });

  /// Rail glass sits [railMargin] in from the edge, [railWidth] wide;
  /// popovers anchor against it.
  static const double railMargin = 16;

  /// Rail top below the safe area: about three inches down, nearer the
  /// thumb.
  static const double railTop = 208;
  static const double railWidth = 60;

  String get _subtitle {
    final parts = [
      subtitleLead?.trim() ?? '',
      formatMinutesLeft(pagesLeft), // empty at 0 pages
    ].where((p) => p.isNotEmpty);
    return parts.join(' · ').toUpperCase();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final comic = ComicTokens.watch(ref, context, accent);
    final scheme = context.scheme;

    // Close sits beside the title in both layouts.
    final back = _ActionButton(
      key: const Key('reader.back'),
      label: 'Close',
      icon: Icons.close,
      onTap: onClose,
    );
    final titleBlock = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTitleTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: scheme.tx,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            _subtitle,
            style: context.monoCaption.copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.66,
              color: scheme.t2,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
    final actions = <Widget>[
      if (onSleepTimer != null)
        _SleepButton(
          key: const Key('reader.sleep'),
          remaining: sleepRemaining ?? () => null,
          onTap: onSleepTimer!,
          accent: accent,
        ),
      _ActionButton(
        key: const Key('reader.bookmark'),
        label: 'Bookmark',
        icon: isBookmarked ? Icons.bookmark : Icons.bookmark_border,
        iconColor: isBookmarked ? accent : null,
        onTap: () {
          HapticFeedback.mediumImpact();
          onBookmark();
        },
      ),
      Semantics(
        label: 'Reader settings',
        button: true,
        selected: isSettingsOpen,
        excludeSemantics: true,
        child: GestureDetector(
          key: const Key('reader.aa'),
          behavior: HitTestBehavior.opaque,
          onTap: () {
            HapticFeedback.selectionClick();
            onSettings();
          },
          // 44pt tall hit area around the 36pt pill.
          child: SizedBox(
            height: 44,
            child: Center(
              child: Container(
                height: 36,
                constraints: const BoxConstraints(minWidth: 44),
                padding: EdgeInsets.symmetric(horizontal: rail ? 0 : 14),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isSettingsOpen ? accent : scheme.hairStrong,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(
                  'Aa',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.34,
                    color: isSettingsOpen ? Scheme.onAccent(accent) : scheme.tx,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      if (inlineMore case final items?)
        for (final (icon, label, onTap) in items)
          _ActionButton(
            label: label,
            icon: icon,
            onTap: () {
              HapticFeedback.selectionClick();
              onTap();
            },
          )
      else
        _ActionButton(
          key: const Key('reader.more'),
          label: 'More',
          icon: Icons.more_horiz,
          fill: isMoreOpen ? scheme.hairStrong : null,
          onTap: () {
            HapticFeedback.selectionClick();
            onMore();
          },
        ),
      if (rail && onClaude != null)
        Opacity(
          opacity: claudeMode == ClaudePanelMode.ghost ? 0.5 : 1,
          child: _ActionButton(
            key: const Key('reader.claude'),
            label: 'Claude',
            icon: claudeMode == ClaudePanelMode.off
                ? Icons.auto_awesome_outlined
                : Icons.auto_awesome,
            iconColor: claudeMode == ClaudePanelMode.off ? null : accent,
            onTap: () {
              HapticFeedback.selectionClick();
              onClaude!();
            },
          ),
        ),
    ];

    Widget glass(Widget child, {required EdgeInsets padding}) => Container(
      decoration: comic.hardShadow
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: comic.ink, width: comic.borderWidth),
              boxShadow: comic.cardShadow,
            )
          : null,
      child: LiquidGlass(radius: 22, padding: padding, child: child),
    );

    if (rail) {
      const gap = SizedBox(height: 8);
      return Stack(
        children: [
          Positioned(
            top: 0,
            left: railOnLeft ? 0 : null,
            right: railOnLeft ? null : 0,
            child: SafeArea(
              left: railOnLeft,
              right: !railOnLeft,
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  railMargin,
                  railTop,
                  railMargin,
                  railMargin,
                ),
                child: glass(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  SizedBox(
                    width: railWidth,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // The running sleep pill ("45m") is wider than the
                        // rail; scale it down rather than overflow.
                        for (final (i, a) in actions.indexed) ...[
                          if (i > 0) gap,
                          FittedBox(fit: BoxFit.scaleDown, child: a),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: railOnLeft ? null : 0,
            right: railOnLeft ? 0 : null,
            child: SafeArea(
              left: !railOnLeft,
              right: railOnLeft,
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.all(railMargin),
                child: glass(
                  padding: const EdgeInsets.fromLTRB(4, 4, 14, 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      back,
                      const SizedBox(width: 6),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 280),
                        child: titleBlock,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    final inset = LayoutBreakpoint.isTablet(context) ? 20.0 : 12.0;
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(inset, 8, inset, 0),
        child: glass(
          padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
          Row(
            children: [
              back,
              const SizedBox(width: 8),
              Expanded(child: titleBlock),
              for (final a in actions) ...[const SizedBox(width: 8), a],
            ],
          ),
        ),
      ),
    );
  }
}

/// 44pt circular top-bar action (Apple's minimum touch target).
class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final Color? iconColor;
  final Color? fill;

  const _ActionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.iconColor,
    this.fill,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      button: true,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: fill ?? Colors.transparent,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 22, color: iconColor ?? context.scheme.tx),
        ),
      ),
    );
  }
}

/// Moon: plain outline when off; accent pill with ceiled minutes left when on.
class _SleepButton extends StatefulWidget {
  final Duration? Function() remaining;
  final VoidCallback onTap;
  final Color accent;

  const _SleepButton({
    super.key,
    required this.remaining,
    required this.onTap,
    required this.accent,
  });

  @override
  State<_SleepButton> createState() => _SleepButtonState();
}

class _SleepButtonState extends State<_SleepButton> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _syncTick();
  }

  @override
  void didUpdateWidget(_SleepButton old) {
    super.didUpdateWidget(old);
    _syncTick();
  }

  // ponytail: 1s re-read so the minute label flips on time; only while the
  // timer is on, so nothing ticks while it's off.
  void _syncTick() {
    final on = widget.remaining() != null;
    if (on && _tick == null) {
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(_syncTick);
      });
    } else if (!on && _tick != null) {
      _tick?.cancel();
      _tick = null;
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final left = widget.remaining();
    final mins = left == null ? null : ceilMinutes(left);
    final on = mins != null;
    final fg = Scheme.onAccent(widget.accent);
    return Semantics(
      label: on ? 'Sleep timer, $mins minutes left' : 'Sleep timer off',
      button: true,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          widget.onTap();
        },
        child: SizedBox(
          height: 44,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              height: on ? 36 : 44,
              constraints: const BoxConstraints(minWidth: 44),
              padding: EdgeInsets.symmetric(horizontal: on ? 12 : 0),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on ? widget.accent : widget.accent.withValues(alpha: 0),
                borderRadius: BorderRadius.circular(22),
              ),
              child: AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                child: on
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.bedtime, size: 18, color: fg),
                          const SizedBox(width: 4),
                          Text(
                            '${mins}m',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              fontFeatures: const [FontFeature.tabularFigures()],
                              color: fg,
                            ),
                          ),
                        ],
                      )
                    : Icon(Icons.bedtime_outlined, size: 22, color: scheme.tx),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
