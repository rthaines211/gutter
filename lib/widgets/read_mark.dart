import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_theme.dart';
import '../config/comic_style.dart';
import '../config/scheme.dart';
import '../providers/comic_style_provider.dart';
import 'halftone_overlay.dart';

/// Read state overlay for an issue cover. Fill the cover's Stack with it.
///
/// At rest it is the existing green check badge (top right). When [isRead]
/// flips false → true for the same [issueId], it plays a one-shot mark whose
/// look follows Comic Style:
///  * off — the badge pops in
///  * Ink + Halftone — an ink-outlined mono READ stamp slams down, then the badge pops
///  * Full Pop — a Bangers "READ!" stamp with a hard shadow and Ben-Day dots
///
/// The issue id guard matters: sliver grids reuse element state by index, so
/// after a status re-sort a different issue can land in this slot.
class ReadMark extends ConsumerStatefulWidget {
  final String issueId;
  final bool isRead;
  final Color accent;
  final double badgeSize;

  const ReadMark({
    super.key,
    required this.issueId,
    required this.isRead,
    required this.accent,
    this.badgeSize = 18,
  });

  @override
  ConsumerState<ReadMark> createState() => _ReadMarkState();
}

class _ReadMarkState extends ConsumerState<ReadMark>
    with SingleTickerProviderStateMixin {
  static const _stampRun = Duration(milliseconds: 1100);
  static const _badgeRun = Duration(milliseconds: 420);

  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this);
  }

  @override
  void didUpdateWidget(ReadMark old) {
    super.didUpdateWidget(old);
    if (old.issueId != widget.issueId) {
      _c.value = 0;
      _c.stop();
      return;
    }
    if (!old.isRead && widget.isRead) {
      final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
      if (reduced) return;
      final comic = ComicTokens.of(
          ref.read(comicStyleProvider), context.scheme, widget.accent);
      _c.duration = comic.benDay ? _stampRun : _badgeRun;
      _c.forward(from: 0);
    } else if (old.isRead && !widget.isRead) {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final comic = ComicTokens.watch(ref, context, widget.accent);
    if (!widget.isRead && !_c.isAnimating) return const SizedBox.shrink();

    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final animating = _c.isAnimating;
          final t = _c.value;
          double iv(double a, double b, [Curve c = Curves.linear]) =>
              c.transform(((t - a) / (b - a)).clamp(0.0, 1.0));

          final stamped = comic.benDay;
          final badgeScale = !animating
              ? 1.0
              : stamped
                  ? iv(0.72, 1.0, Curves.easeOutBack)
                  : iv(0.0, 1.0, Curves.easeOutBack);

          return Stack(
            fit: StackFit.expand,
            children: [
              if (animating && stamped)
                Center(
                  child: _Stamp(
                    comic: comic,
                    // slam in, hold, lift off
                    scale: 2.3 - 1.3 * iv(0.0, 0.30, Curves.easeOutBack),
                    angle: -24 + 14 * iv(0.0, 0.30, Curves.easeOut),
                    opacity: iv(0.0, 0.10) * (1 - iv(0.62, 0.80)),
                  ),
                ),
              Positioned(
                top: 6,
                right: 6,
                child: Transform.scale(
                  scale: badgeScale,
                  child: _Badge(size: widget.badgeSize),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final double size;
  const _Badge({required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppTheme.green,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: AppTheme.green.withValues(alpha: 0.5), blurRadius: 6),
        ],
      ),
      child: Icon(Icons.check_rounded,
          size: size * 0.62, color: Scheme.onAccent(AppTheme.green)),
    );
  }
}

class _Stamp extends StatelessWidget {
  final ComicTokens comic;
  final double scale;
  final double angle;
  final double opacity;

  const _Stamp({
    required this.comic,
    required this.scale,
    required this.angle,
    required this.opacity,
  });

  @override
  Widget build(BuildContext context) {
    final Widget face;
    if (comic.displayFont) {
      // Full Pop: sits on cover art, so fill/ink are literal (see CaptionBox).
      face = Container(
        padding: const EdgeInsets.fromLTRB(12, 2, 12, 0),
        decoration: BoxDecoration(
          color: AppTheme.green,
          border: Border.all(color: const Color(0xFF111111), width: 2.5),
          boxShadow: const [
            BoxShadow(color: Color(0xFF111111), offset: Offset(4, 4)),
          ],
        ),
        child: Stack(
          children: [
            Text(
              'READ!',
              style: TextStyle(
                fontFamily: 'Bangers',
                fontSize: 30,
                letterSpacing: 1.8,
                color: Scheme.onAccent(AppTheme.green),
              ),
            ),
            const HalftoneOverlay(
              opacity: 0.18,
              color: Colors.black,
              dotSpacing: 6,
              dotRadius: 1.2,
            ),
          ],
        ),
      );
    } else {
      // Ink + Halftone: mono stamp on a scheme surface, ink outline.
      face = Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: context.scheme.s1,
          border: Border.all(color: comic.ink, width: 2),
        ),
        child: Text(
          'READ',
          style: AppTheme.monoLabel.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 2.2,
            color: comic.ink,
          ),
        ),
      );
    }

    return Opacity(
      opacity: opacity.clamp(0.0, 1.0),
      child: Transform.rotate(
        angle: angle * math.pi / 180,
        child: Transform.scale(scale: scale, child: face),
      ),
    );
  }
}
