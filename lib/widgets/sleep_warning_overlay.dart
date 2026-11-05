import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_theme.dart';
import '../config/comic_style.dart';
import '../config/scheme.dart';
import 'caption_box.dart';
import 'halftone_overlay.dart';
import 'liquid_glass.dart';

/// Design B "Meanwhile…": shown [lead] before the sleep timer releases the
/// wakelock. The page dims (and, with Ben-Day on, accent dots creep in from
/// the edges) as the deadline nears; captions narrate a live countdown.
///
/// Ignoring it lets the screen sleep. Swiping the captions/controls hides it
/// without touching the timer. Taps on the dim are swallowed so the page
/// underneath doesn't turn.
class SleepWarningOverlay extends ConsumerStatefulWidget {
  /// Time left before the screen sleeps, re-read every second.
  final Duration Function() remaining;

  /// The warning lead; the dim and dots grow over it.
  final Duration lead;
  final Color accent;
  final VoidCallback onExtend;
  final VoidCallback onRestart;
  final VoidCallback onCancel;
  final VoidCallback onDismiss;

  const SleepWarningOverlay({
    super.key,
    required this.remaining,
    required this.lead,
    required this.accent,
    required this.onExtend,
    required this.onRestart,
    required this.onCancel,
    required this.onDismiss,
  });

  @override
  ConsumerState<SleepWarningOverlay> createState() =>
      _SleepWarningOverlayState();
}

class _SleepWarningOverlayState extends ConsumerState<SleepWarningOverlay>
    with TickerProviderStateMixin {
  Timer? _tick;
  late Duration _left;

  late final _entrance = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 450))
    ..forward();
  late final _breathe = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1400))
    ..repeat(reverse: true);
  late final _wobble =
      AnimationController(vsync: this, duration: const Duration(seconds: 4))
        ..repeat();
  // Built once: a CurvedAnimation made in build() leaks a parent listener
  // per rebuild, and the countdown rebuilds every second.
  late final _slide =
      CurvedAnimation(parent: _entrance, curve: Curves.easeOutBack);
  late final _breatheCurve =
      CurvedAnimation(parent: _breathe, curve: Curves.easeInOut);
  late final _breatheScale =
      Tween(begin: 1.0, end: 1.03).animate(_breatheCurve);

  @override
  void initState() {
    super.initState();
    _left = widget.remaining();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _left = widget.remaining());
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _entrance.value = 1;
      _breathe
        ..stop()
        ..value = 0;
      _wobble
        ..stop()
        ..value = 0;
    } else {
      if (!_breathe.isAnimating) _breathe.repeat(reverse: true);
      if (!_wobble.isAnimating) _wobble.repeat();
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    _slide.dispose();
    _breatheCurve.dispose();
    _entrance.dispose();
    _breathe.dispose();
    _wobble.dispose();
    super.dispose();
  }

  String get _countdown {
    final total = _left.inSeconds;
    return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
  }

  double get _progress {
    final lead = widget.lead.inMilliseconds;
    if (lead <= 0) return 1;
    return (1 - _left.inMilliseconds / lead).clamp(0.0, 1.0);
  }

  VoidCallback _tap(VoidCallback action) => () {
        HapticFeedback.selectionClick();
        action();
      };

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final comic = ComicTokens.watch(ref, context, widget.accent);
    final p = _progress;
    final dim = scheme.dark ? Colors.black : scheme.tx;


    final countdown = Text(
      _countdown,
      key: const Key('sleep.countdown'),
      style: AppTheme.displayTextStyle(comic, fontSize: 56).copyWith(
        fontFeatures: const [FontFeature.tabularFigures()],
        height: 1,
      ),
    );

    final controls = _Controls(
      comic: comic,
      accent: widget.accent,
      wobble: _wobble,
      onExtend: _tap(widget.onExtend),
      onRestart: _tap(widget.onRestart),
      onCancel: _tap(widget.onCancel),
    );

    final Widget content;
    // Off is the only style without hard shadows: it gets the glass card.
    // Ink & Halftone keeps the caption layout; CaptionBox picks its look.
    if (comic.hardShadow) {
      final capStyle = AppTheme.displayTextStyle(comic, fontSize: 22);
      content = Stack(
        children: [
          Align(
            alignment: const Alignment(-0.9, -0.55),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CaptionBox(
                  comic: comic,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 4),
                    child: Text('MEANWHILE…', style: capStyle),
                  ),
                ),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.only(left: 22),
                  child: ScaleTransition(
                    scale: _breatheScale,
                    alignment: Alignment.centerLeft,
                    child: CaptionBox(
                      comic: comic,
                      rightSide: true,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text('SCREEN SLEEPS IN', style: capStyle),
                            const SizedBox(width: 12),
                            countdown,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Align(
            alignment: const Alignment(0.92, 0.88),
            child: controls,
          ),
        ],
      );
    } else {
      content = Align(
        alignment: const Alignment(0, 0.85),
        child: LiquidGlass(
          radius: 24,
          padding: const EdgeInsets.all(20),
          child: DefaultTextStyle.merge(
            style: TextStyle(color: scheme.tx),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Breathe the copy only; buttons stay still under a finger.
                ScaleTransition(
                  scale: _breatheScale,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Screen sleeping in',
                          style: TextStyle(fontSize: 17, color: scheme.t2)),
                      const SizedBox(height: 6),
                      countdown,
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                controls,
              ],
            ),
          ),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // Swallow taps outside the controls: the page underneath must not turn.
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {},
          child: ColoredBox(color: dim.withValues(alpha: 0.35 * p)),
        ),
        if (comic.benDay)
          IgnorePointer(
            child: ShaderMask(
              blendMode: BlendMode.dstIn,
              // Clear centre shrinks as p grows, so dots creep in from edges.
              shaderCallback: (rect) => RadialGradient(
                radius: 0.9,
                colors: const [Colors.transparent, Colors.black],
                stops: [0.95 - 0.5 * p, 1.0],
              ).createShader(rect),
              child: Stack(children: [
                HalftoneOverlay(
                  color: widget.accent,
                  opacity: 0.55,
                  dotSpacing: 9,
                  dotRadius: 1.6,
                ),
              ]),
            ),
          ),
        SafeArea(
          child: Dismissible(
            key: const ValueKey('sleep-warning'),
            direction: DismissDirection.horizontal,
            onDismissed: (_) => widget.onDismiss(),
            child: FadeTransition(
              opacity: _entrance,
              child: AnimatedBuilder(
                animation: _slide,
                builder: (context, child) => Transform.translate(
                  offset: Offset(-40 * (1 - _slide.value), 0),
                  child: child,
                ),
                child: content,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Restart and Off stacked beside the +15 primary.
class _Controls extends StatelessWidget {
  final ComicTokens comic;
  final Color accent;
  final Animation<double> wobble;
  final VoidCallback onExtend;
  final VoidCallback onRestart;
  final VoidCallback onCancel;

  const _Controls({
    required this.comic,
    required this.accent,
    required this.wobble,
    required this.onExtend,
    required this.onRestart,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final onAccent = Scheme.onAccent(accent);
    final Widget primary;
    if (comic.hardShadow) {
      primary = Semantics(
        button: true,
        label: '+15 min',
        excludeSemantics: true,
        child: GestureDetector(
          key: const Key('sleep.extend'),
          behavior: HitTestBehavior.opaque,
          onTap: onExtend,
          child: AnimatedBuilder(
            animation: wobble,
            // ±3° sway over the 4s loop.
            builder: (context, child) => Transform.rotate(
              angle: math.sin(wobble.value * 2 * math.pi) * 3 * math.pi / 180,
              child: child,
            ),
            child: CustomPaint(
              key: const Key('sleep.burst'),
              size: const Size.square(150),
              painter: _BurstPainter(
                fill: accent,
                ink: comic.ink,
                borderWidth: comic.borderWidth,
                shadows: comic.cardShadow,
              ),
              child: SizedBox.square(
                dimension: 150,
                child: Center(
                  child: Transform.rotate(
                    angle: -6 * math.pi / 180,
                    child: Text(
                      '+15\nMIN!',
                      textAlign: TextAlign.center,
                      style: AppTheme.displayTextStyle(comic, fontSize: 30)
                          .copyWith(color: onAccent, height: 1),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    } else {
      primary = Semantics(
        button: true,
        label: '+15 min',
        excludeSemantics: true,
        child: GestureDetector(
          onTap: onExtend,
          child: Container(
            key: const Key('sleep.extend'),
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 22),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text('+15 min',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: onAccent)),
          ),
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        IntrinsicWidth(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SideButton(
                buttonKey: const Key('sleep.restart'),
                comic: comic,
                label: 'Restart',
                icon: Icons.replay,
                onTap: onRestart,
              ),
              const SizedBox(height: 14),
              _SideButton(
                buttonKey: const Key('sleep.off'),
                comic: comic,
                label: 'Off',
                icon: Icons.bedtime_off_outlined,
                onTap: onCancel,
              ),
            ],
          ),
        ),
        const SizedBox(width: 14),
        primary,
      ],
    );
  }
}

/// Solid scheme-surface button. Off uses this too: never a ghost.
class _SideButton extends StatelessWidget {
  /// On the decorated box itself, so tests can read its fill.
  final Key buttonKey;
  final ComicTokens comic;
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _SideButton({
    required this.buttonKey,
    required this.comic,
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          key: buttonKey,
          height: 52,
          constraints: const BoxConstraints(minWidth: 150),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            color: scheme.s2,
            borderRadius: BorderRadius.circular(comic.hardShadow ? 10 : 14),
            border: comic.hardShadow
                ? Border.all(color: comic.ink, width: comic.borderWidth)
                : null,
            boxShadow: comic.hardShadow ? comic.cardShadow : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: scheme.tx),
              const SizedBox(width: 8),
              Text(label,
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: scheme.tx)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 12-point starburst: hard shadow, accent fill, ink outline.
class _BurstPainter extends CustomPainter {
  final Color fill;
  final Color ink;
  final double borderWidth;
  final List<BoxShadow> shadows;

  _BurstPainter({
    required this.fill,
    required this.ink,
    required this.borderWidth,
    required this.shadows,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final outer = size.shortestSide / 2 - borderWidth;
    final inner = outer * 0.74;
    final path = Path();
    for (var i = 0; i < 24; i++) {
      final r = i.isEven ? outer : inner;
      final a = -math.pi / 2 + i * math.pi / 12;
      final pt = c + Offset(math.cos(a) * r, math.sin(a) * r);
      i == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
    }
    path.close();
    for (final s in shadows) {
      canvas.drawPath(
          path.shift(s.offset),
          Paint()
            ..color = s.color
            ..maskFilter = s.blurRadius > 0
                ? MaskFilter.blur(BlurStyle.normal, s.blurSigma)
                : null);
    }
    canvas.drawPath(path, Paint()..color = fill);
    canvas.drawPath(
        path,
        Paint()
          ..color = ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = borderWidth
          ..strokeJoin = StrokeJoin.miter);
  }

  @override
  bool shouldRepaint(_BurstPainter old) =>
      old.fill != fill ||
      old.ink != ink ||
      old.borderWidth != borderWidth ||
      old.shadows != shadows;
}
