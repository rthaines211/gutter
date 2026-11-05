import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_theme.dart';
import '../config/comic_style.dart';
import '../config/scheme.dart';
import '../providers/accent_provider.dart';

/// Cold-launch splash built from the Longbox mark.
///
/// The shelf draws in, the three upright spines drop onto it, then the accent
/// spine lands and tips forward to the mark's resting -8°, so the animation
/// ends on the exact app icon. The wordmark follows and the overlay fades out.
///
/// The app is built underneath from the first frame, so this never delays
/// launch sync or the first screen. Taps on the overlay skip to the fade and
/// never reach the hidden app. Skipped entirely when the OS asks for reduced
/// motion.
///
/// Geometry mirrors `LongboxMark` (120×120 grid).
class LongboxSplash extends ConsumerStatefulWidget {
  final Widget child;

  /// Total run, including the 465ms fade-out at the end.
  static const duration = Duration(milliseconds: 3100);

  const LongboxSplash({super.key, required this.child});

  @override
  ConsumerState<LongboxSplash> createState() => _LongboxSplashState();
}

class _LongboxSplashState extends ConsumerState<LongboxSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: LongboxSplash.duration)
      // A status listener, not forward()'s future: a skip's forward(from:)
      // cancels that future.
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed && mounted) {
          setState(() => _done = true);
        }
      });
  }

  /// Where the fade-out begins; a tap jumps here.
  static const _fadeStart = 0.85;

  bool _done = false;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _done = true;
      return;
    }
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Always a Stack with the child first: swapping the Stack out when the
    // splash ends would remount the Navigator below and drop its routes.
    if (_done) {
      return Stack(
        textDirection: TextDirection.ltr,
        fit: StackFit.expand,
        children: [widget.child],
      );
    }
    final scheme = context.scheme;
    final accent = ref.watch(accentProvider).value ?? AppTheme.accent;
    final comic = ComicTokens.watch(ref, context, accent);
    final spine = scheme.dark ? const Color(0xFFF8F0DD) : scheme.tx;
    // Big on iPad. Shortest side, not LayoutBreakpoint.isTablet: a landscape
    // iPhone is wider than 768 but too short for a 400pt mark.
    final tablet = MediaQuery.sizeOf(context).shortestSide >= 600;
    final markSize = tablet ? 400.0 : 132.0;
    final wordSize = tablet ? 79.0 : 26.0;

    return Stack(
      textDirection: TextDirection.ltr,
      fit: StackFit.expand,
      children: [
        widget.child,
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              final t = _c.value;
              double iv(double a, double b, [Curve curve = Curves.linear]) =>
                  curve.transform(((t - a) / (b - a)).clamp(0.0, 1.0));

              final word = iv(0.66, 0.80, Curves.easeOut);
              // Whatever is on screen owns the taps: the splash swallows them
              // (a tap skips to the fade) until the fade starts.
              return IgnorePointer(
                ignoring: t >= _fadeStart,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _c.forward(from: _fadeStart),
                  child: Opacity(
                    opacity: 1 - iv(_fadeStart, 1.0, Curves.easeIn),
                    child: ColoredBox(
                      color: scheme.bg,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CustomPaint(
                              size: Size.square(markSize),
                              painter: _SplashMarkPainter(
                                shelf: iv(0.0, 0.18, Curves.easeOutCubic),
                                spines: [
                                  iv(0.12, 0.38, Curves.easeOutBack),
                                  iv(0.16, 0.42, Curves.easeOutBack),
                                  iv(0.20, 0.46, Curves.easeOutBack),
                                ],
                                pullIn: iv(0.28, 0.50, Curves.easeOutBack),
                                tip: iv(0.50, 0.70, Curves.elasticOut),
                                accent: accent,
                                spine: spine,
                              ),
                            ),
                            SizedBox(height: tablet ? 0 : 18),
                            Opacity(
                              opacity: word,
                              child: Transform.translate(
                                offset: Offset(0, 6 * (1 - word)),
                                child: Text(
                                  'LONGBOX',
                                  textDirection: TextDirection.ltr,
                                  style: AppTheme.displayTextStyle(comic, fontSize: wordSize)
                                      .copyWith(
                                    color: scheme.tx,
                                    letterSpacing: wordSize * 0.14,
                                    decoration: TextDecoration.none,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SplashMarkPainter extends CustomPainter {
  final double shelf;
  final List<double> spines;
  final double pullIn;
  final double tip;
  final Color accent;
  final Color spine;

  const _SplashMarkPainter({
    required this.shelf,
    required this.spines,
    required this.pullIn,
    required this.tip,
    required this.accent,
    required this.spine,
  });

  static const _grid = 120.0;
  static const _drop = 40.0;
  static const _rects = [
    Rect.fromLTWH(22, 26, 16, 68),
    Rect.fromLTWH(66, 30, 16, 64),
    Rect.fromLTWH(88, 36, 12, 58),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / _grid;

    if (shelf > 0) {
      canvas.drawLine(
        Offset(18 * k, 100 * k),
        Offset((18 + 84 * shelf) * k, 100 * k),
        Paint()
          ..color = spine
          ..strokeWidth = 7 * k
          ..strokeCap = StrokeCap.round,
      );
    }

    for (var i = 0; i < _rects.length; i++) {
      final t = spines[i];
      if (t <= 0) continue;
      final r = _rects[i];
      final dy = -_drop * (1 - t);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(r.left * k, (r.top + dy) * k, r.width * k, r.height * k),
          Radius.circular(2 * k),
        ),
        Paint()..color = spine.withValues(alpha: t.clamp(0.0, 1.0)),
      );
    }

    if (pullIn > 0) {
      canvas.save();
      canvas.translate(0, -_drop * (1 - pullIn) * k);
      canvas.translate(52 * k, 56 * k);
      canvas.rotate(-8 * tip * math.pi / 180);
      canvas.translate(-52 * k, -56 * k);
      canvas.drawRect(
        Rect.fromLTWH(44 * k, 18 * k, 17 * k, 76 * k),
        Paint()..color = accent.withValues(alpha: pullIn.clamp(0.0, 1.0)),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_SplashMarkPainter old) => true;
}
