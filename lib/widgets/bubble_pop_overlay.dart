import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Largest pop-out, as a multiple of the balloon on screen. 2.6x hid the art
/// around most balloons (spike 2026-10-11: 88 % of 849 steps); 1.6x, placed by
/// [artCost], hides 78 % less and still reads clearly bigger than the page.
const maxPopScale = 1.6;

/// Largest pop-out for a chain of joined balloons. A chain is already big:
/// at 1.6x three in four chain steps hid a lot of art (audit 2026-10-12,
/// 1,432 chain steps, mean 4,442 pt² vs 1,911 for one balloon).
const chainPopScale = 1.3;

/// A balloon pop-out that cannot grow at least this much is not drawn.
const minPopGrowth = 1.15;

/// Where a balloon pops out: the on-screen crop grown by up to [maxScale],
/// capped at 92 % of the screen width and 45 % of its height (80 % on a wide
/// screen), kept 8 px inside the screen.
/// With a [tail] tip (on screen) it grows out of the tail, which stays on the
/// speaker; without one it grows away from the nearer edges, keeping its
/// relative place on screen. [clamp] false leaves a tailed pop-out where its
/// tail puts it, even off screen ([popoutSlide] then moves the page).
/// With [heightCap] the height limit is that fraction of the screen instead
/// of 45 % (80 % on a wide screen). [minScale] stops a crop wider than the
/// caps allow from shrinking: a panel lifts out at its own size instead.
/// With [artCost] (art hidden under a screen rect, the balloon's own spot not
/// counted), it moves to wherever, still covering most of the balloon, hides
/// the least art; that placement keeps it only when nothing hides less.
Rect popoutRect(
  Rect onScreen,
  Size screen, {
  Offset? tail,
  bool clamp = true,
  double Function(Rect)? artCost,
  double maxScale = maxPopScale,
  double? heightCap,
  double minScale = 0,
}) {
  final base = _popoutRect(
    onScreen,
    screen,
    tail: tail,
    clamp: clamp,
    maxScale: maxScale,
    heightCap: heightCap,
    minScale: minScale,
  );
  if (artCost == null || !clamp) return base;
  final w = base.width,
      h = base.height,
      area = onScreen.width * onScreen.height;
  var best = base, bestCost = artCost(base);
  // ponytail: a 9 x 9 grid of placements; enough on the spike's 849 steps.
  for (var i = 0; i <= 8; i++) {
    for (var j = 0; j <= 8; j++) {
      final r = Rect.fromLTWH(
        (onScreen.left - i / 8 * (w - onScreen.width)).clamp(
          8,
          math.max(8, screen.width - w - 8),
        ),
        (onScreen.top - j / 8 * (h - onScreen.height)).clamp(
          8,
          math.max(8, screen.height - h - 8),
        ),
        w,
        h,
      );
      final o = r.intersect(onScreen);
      if (o.width <= 0 || o.height <= 0 || o.width * o.height < 0.6 * area) {
        continue;
      }
      final c = artCost(r);
      if (c < bestCost - 1) {
        best = r;
        bestCost = c;
      }
    }
  }
  return best;
}

Rect _popoutRect(
  Rect onScreen,
  Size screen, {
  Offset? tail,
  bool clamp = true,
  double maxScale = maxPopScale,
  double? heightCap,
  double minScale = 0,
}) {
  final r = math.max(
    minScale,
    math.min(
      math.min(
        0.92 * screen.width / onScreen.width,
        // a sideways screen is short: 45 % of it is about what a balloon already is.
        // A panel pop-out passes its own cap (0.85).
        (heightCap ?? (screen.width > screen.height ? 0.8 : 0.45)) *
            screen.height /
            onScreen.height,
      ),
      maxScale,
    ),
  );
  final w = onScreen.width * r, h = onScreen.height * r;
  if (tail != null && !clamp) {
    return Rect.fromLTWH(
      tail.dx + r * (onScreen.left - tail.dx),
      tail.dy + r * (onScreen.top - tail.dy),
      w,
      h,
    );
  }
  if (tail != null) {
    return Rect.fromLTWH(
      (tail.dx + r * (onScreen.left - tail.dx)).clamp(
        8,
        math.max(8, screen.width - w - 8),
      ),
      (tail.dy + r * (onScreen.top - tail.dy)).clamp(
        8,
        math.max(8, screen.height - h - 8),
      ),
      w,
      h,
    );
  }
  return Rect.fromLTWH(
    _place(onScreen.left, onScreen.width, w, screen.width),
    _place(onScreen.top, onScreen.height, h, screen.height),
    w,
    h,
  );
}

/// How far to slide the page so [popout] sits 8 px inside the screen.
Offset popoutSlide(Rect popout, Size screen) {
  double fit(double lo, double hi, double extent) =>
      lo < 8 ? 8 - lo : (hi > extent - 8 ? extent - 8 - hi : 0);
  return Offset(
    fit(popout.left, popout.right, screen.width),
    fit(popout.top, popout.bottom, screen.height),
  );
}

/// Start of a span grown from [size] to [grown], keeping its fraction of the
/// free room inside an 8 px margin of [extent].
double _place(double start, double size, double grown, double extent) {
  final room = extent - 16 - size;
  final f = room > 0 ? ((start - 8) / room).clamp(0.0, 1.0) : 0.5;
  return 8 + f * (extent - 16 - grown);
}

/// One balloon of a pop-out: its crop in page pixels and the cut-out covering
/// exactly that crop (null: a rounded rect, for a balloon with no outline).
typedef PopPart = ({Rect src, ui.Image? mask});

/// Style C: one balloon, or a chain of joined balloons, enlarged over the
/// undimmed page, cut along each one's mask, with a soft shadow.
class BubblePopOverlay extends StatefulWidget {
  const BubblePopOverlay({
    super.key,
    required this.pageImage,
    required this.parts,
    required this.onScreen,
    this.tail,
    this.artCost,
    required this.label,
    this.maxScale,
    this.heightCap,
    this.minScale = 0,
    this.minGrowth = minPopGrowth,
  });

  final ImageProvider pageImage;
  final List<PopPart> parts;

  /// Where the parts' crops, together, currently sit on screen.
  final Rect onScreen;

  /// The tail tip on screen, when there is one.
  final Offset? tail;

  /// Art hidden under a screen rect (see [popoutRect]); null places by tail alone.
  final double Function(Rect)? artCost;

  /// The first balloon's label: a new label animates in afresh.
  final int label;

  /// Largest growth; null means the balloon rule (1.6x, 1.3x for a chain).
  final double? maxScale;

  /// Height limit as a fraction of the screen; null means the balloon rule.
  final double? heightCap;

  /// Smallest growth drawn at all (see [popoutRect]); a panel passes 1.
  final double minScale;

  /// Below this growth nothing is drawn: a balloon copy barely bigger than
  /// the balloon only looks doubled. A panel passes 1: it lifts out regardless.
  final double minGrowth;

  @override
  State<BubblePopOverlay> createState() => _BubblePopOverlayState();
}

class _BubblePopOverlayState extends State<BubblePopOverlay> {
  ImageStream? _stream;
  ImageInfo? _info;
  late final _listener = ImageStreamListener((info, _) {
    if (!mounted) return;
    setState(() {
      _info?.dispose();
      _info = info;
    });
  });

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(BubblePopOverlay old) {
    super.didUpdateWidget(old);
    if (old.pageImage != widget.pageImage) _resolve();
  }

  void _resolve() {
    final stream = widget.pageImage.resolve(
      createLocalImageConfiguration(context),
    );
    if (stream.key == _stream?.key) return;
    _stream?.removeListener(_listener);
    _stream = stream..addListener(_listener);
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    _info?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final image = _info?.image;
    if (image == null) return const SizedBox.shrink();
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, c) {
          final to = popoutRect(
            widget.onScreen,
            c.biggest,
            tail: widget.tail,
            artCost: widget.artCost,
            maxScale:
                widget.maxScale ??
                (widget.parts.length > 1 ? chainPopScale : maxPopScale),
            heightCap: widget.heightCap,
            minScale: widget.minScale,
          );
          // Already about as big as it can get: a copy over it would only look doubled.
          if (to.width < widget.minGrowth * widget.onScreen.width) {
            return const SizedBox.shrink();
          }
          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 150),
            child: TweenAnimationBuilder<double>(
              key: ValueKey(widget.label),
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
              builder: (_, t, _) => CustomPaint(
                size: c.biggest,
                painter: BubblePopPainter(
                  page: image,
                  parts: widget.parts,
                  from: widget.onScreen,
                  to: to,
                  t: t,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class BubblePopPainter extends CustomPainter {
  BubblePopPainter({
    required this.page,
    required this.parts,
    required this.from,
    required this.to,
    required this.t,
  });

  final ui.Image page;
  final List<PopPart> parts;
  final Rect from;
  final Rect to;
  final double t;

  static const _shadowOffset = Offset(6, 10);

  @override
  void paint(Canvas canvas, Size size) {
    final all = parts.map((p) => p.src).reduce((a, b) => a.expandToInclude(b));
    final box = Rect.lerp(from, to, t)!;
    final sx = box.width / all.width, sy = box.height / all.height;
    Rect dstOf(Rect src) => Rect.fromLTWH(
      box.left + (src.left - all.left) * sx,
      box.top + (src.top - all.top) * sy,
      src.width * sx,
      src.height * sy,
    );
    final a = t.clamp(0.0, 1.0);
    // Every shadow first, so no balloon's shadow falls on the one it joins.
    for (final p in parts) {
      _shadow(canvas, p, dstOf(p.src), a);
    }
    for (final p in parts) {
      _balloon(canvas, p, dstOf(p.src), a);
    }
  }

  void _shadow(Canvas canvas, PopPart p, Rect dst, double a) {
    final m = p.mask;
    if (m == null) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          dst,
          const Radius.circular(18),
        ).shift(_shadowOffset),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.75 * a)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
      );
      return;
    }
    canvas.saveLayer(
      dst.shift(_shadowOffset).inflate(30),
      Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
    );
    canvas.drawImageRect(
      m,
      _whole(m),
      dst.shift(_shadowOffset),
      Paint()
        ..colorFilter = ColorFilter.mode(
          Colors.black.withValues(alpha: 0.75 * a),
          BlendMode.srcIn,
        ),
    );
    canvas.restore();
  }

  void _balloon(Canvas canvas, PopPart p, Rect dst, double a) {
    final m = p.mask;
    if (m == null) {
      canvas.save();
      canvas.clipRRect(RRect.fromRectAndRadius(dst, const Radius.circular(18)));
      canvas.drawImageRect(
        page,
        p.src,
        dst,
        Paint()
          ..filterQuality = FilterQuality.medium
          ..color = Colors.white.withValues(alpha: a),
      );
      canvas.restore();
      return;
    }
    canvas.saveLayer(dst, Paint()..color = Colors.white.withValues(alpha: a));
    canvas.drawImageRect(
      page,
      p.src,
      dst,
      Paint()..filterQuality = FilterQuality.medium,
    );
    canvas.drawImageRect(
      m,
      _whole(m),
      dst,
      Paint()
        ..blendMode = BlendMode.dstIn
        ..filterQuality = FilterQuality.medium,
    ); // smooth edge when enlarged
    canvas.restore();
  }

  static Rect _whole(ui.Image m) =>
      Rect.fromLTWH(0, 0, m.width.toDouble(), m.height.toDouble());

  @override
  bool shouldRepaint(BubblePopPainter old) =>
      old.t != t ||
      old.page != page ||
      !listEquals(old.parts, parts) ||
      old.from != from ||
      old.to != to;
}
