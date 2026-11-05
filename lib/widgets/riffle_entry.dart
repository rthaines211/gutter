import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Lifts and settles an issue cover, staggered by [index], like thumbing
/// through a longbox when a series opens.
///
/// Unlike [StaggeredEntry] this never touches opacity: the tile is fully
/// visible at rest and only its transform moves, so a cover that is still
/// loading shows its placeholder instead of a blank gap. That is what kept
/// StaggeredEntry off the library grid.
///
/// [play] is read once, when the tile first mounts. Callers pass true only for tiles built
/// right after the series opens, so tiles scrolled into view later do not
/// riffle. Only the first [maxAnimated] indexes animate.
class RiffleEntry extends StatefulWidget {
  final int index;
  final bool play;
  final Widget child;

  static const duration = Duration(milliseconds: 420);
  static const stagger = Duration(milliseconds: 50);
  static const maxAnimated = 16;

  const RiffleEntry({
    super.key,
    required this.index,
    required this.play,
    required this.child,
  });

  @override
  State<RiffleEntry> createState() => _RiffleEntryState();
}

class _RiffleEntryState extends State<RiffleEntry>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: RiffleEntry.duration);
  }
  Timer? _timer;
  bool _checked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_checked) return;
    _checked = true;
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (!widget.play || reduced || widget.index >= RiffleEntry.maxAnimated) {
      return;
    }
    _timer = Timer(RiffleEntry.stagger * widget.index, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        // 0 → 1 → 0 over the run: up and tilted back at the midpoint.
        final lift = math.sin(math.pi * Curves.easeInOut.transform(_c.value));
        if (lift == 0) return child!;
        return Transform.translate(
          offset: Offset(0, -16 * lift),
          child: Transform(
            alignment: Alignment.bottomCenter,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0012)
              ..rotateX(0.42 * lift),
            child: child,
          ),
        );
      },
    );
  }
}
