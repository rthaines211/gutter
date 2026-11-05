import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_theme.dart';
import '../config/comic_style.dart';
import '../config/scheme.dart';
import 'halftone_overlay.dart';

/// Empty slot in the issue grid for an issue missing from the run.
///
/// Laid out like [IssueGridTile] (cover area + one caption line) so the grid
/// rhythm holds. The slot pulses slowly; with Comic Style on, its outline is
/// ink and it fills with accent Ben-Day dots.
class MissingIssueSlot extends ConsumerStatefulWidget {
  final int number;
  final Color accent;

  const MissingIssueSlot({super.key, required this.number, required this.accent});

  @override
  ConsumerState<MissingIssueSlot> createState() => _MissingIssueSlotState();
}

class _MissingIssueSlotState extends ConsumerState<MissingIssueSlot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduced) {
      _pulse.stop();
      _pulse.value = 1;
    } else if (!_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final comic = ComicTokens.watch(ref, context, widget.accent);
    final scheme = context.scheme;
    final outline = comic.benDay ? comic.ink : scheme.t4;

    return Semantics(
      label: 'Issue ${widget.number} missing',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: FadeTransition(
              opacity: Tween(begin: 0.45, end: 1.0).animate(
                CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
              ),
              child: CustomPaint(
                foregroundPainter: _DashedRRectPainter(
                  color: outline,
                  radius: AppTheme.r12,
                  strokeWidth: comic.benDay ? comic.borderWidth : 1.5,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppTheme.r12),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (comic.benDay)
                        HalftoneOverlay(
                          opacity: 0.22,
                          color: widget.accent,
                          dotSpacing: 7,
                          dotRadius: 1.6,
                        ),
                      Center(
                        child: Text(
                          '#${widget.number}',
                          style: AppTheme.monoLabel.copyWith(
                            fontWeight: FontWeight.w700,
                            color: scheme.t3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '#${widget.number} · Missing',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: widget.accent,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _DashedRRectPainter extends CustomPainter {
  final Color color;
  final double radius;
  final double strokeWidth;

  const _DashedRRectPainter({
    required this.color,
    required this.radius,
    required this.strokeWidth,
  });

  static const _dash = 6.0;
  static const _gap = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    final inset = strokeWidth / 2;
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(inset, inset, size.width - strokeWidth, size.height - strokeWidth),
        Radius.circular(radius),
      ));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    for (final metric in path.computeMetrics()) {
      for (double d = 0; d < metric.length; d += _dash + _gap) {
        canvas.drawPath(metric.extractPath(d, d + _dash), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRRectPainter old) =>
      old.color != color || old.radius != radius || old.strokeWidth != strokeWidth;
}

/// Pops a just-arrived issue into the slot its gap placeholder held.
/// [play] is read once, when the tile first mounts.
class PopIn extends StatefulWidget {
  final bool play;
  final Widget child;

  const PopIn({super.key, required this.play, required this.child});

  @override
  State<PopIn> createState() => _PopInState();
}

class _PopInState extends State<PopIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 550),
    value: 1,
  );
  }
  bool _checked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_checked) return;
    _checked = true;
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (widget.play && !reduced) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: Tween(begin: 0.6, end: 1.0)
          .animate(CurvedAnimation(parent: _c, curve: Curves.easeOutBack)),
      child: FadeTransition(
        opacity: CurvedAnimation(parent: _c, curve: const Interval(0, 0.4)),
        child: widget.child,
      ),
    );
  }
}
