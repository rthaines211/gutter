import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../config/scheme.dart';

/// Segmented series-progress bar: up to 24 segments, gap 2, small radius.
///
/// When [total] exceeds 24, segments become GROUPS of issues rather than a
/// one-to-one mapping. A group renders read (green) only when every issue it
/// covers has been read — i.e. round-down: a group that is only partially
/// read stays unread-styled rather than claiming progress that hasn't
/// happened. This matches reading a green segment as "these issues are
/// fully read"; a partially-filled group rendered green would overstate
/// progress that hasn't happened yet.
///
/// The current-issue highlight lands on whichever group contains
/// [currentIndex] (0-indexed issue position, typically the next unread
/// issue). For a 3-issues-per-group series, issue 30 highlights the group
/// covering issues 30-32, not a fractional slice of it.
///
/// Motion: when [read] goes up (same [total]), segments that just turned green
/// spring in from the left, then the accent marker scales up on its new
/// segment. The first build and any other change render at rest. Segment
/// colours are always the final values, so the keyed containers read the
/// same whether or not an animation is running.
class SeriesProgressBar extends StatefulWidget {
  static const _maxSegments = 24;
  static const _gap = 2.0;
  static const _height = 8.0;

  final int total;
  final int read;
  final int? currentIndex;
  final Color accent;

  const SeriesProgressBar({
    super.key,
    required this.total,
    required this.read,
    this.currentIndex,
    required this.accent,
  });

  @override
  State<SeriesProgressBar> createState() => _SeriesProgressBarState();
}

class _SeriesProgressBarState extends State<SeriesProgressBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
    value: 1,
  );
  }

  /// Segments that turned green in the running animation.
  Set<int> _fresh = const {};

  int get _segments => widget.total < SeriesProgressBar._maxSegments
      ? widget.total
      : SeriesProgressBar._maxSegments;

  int _end(int i) => (widget.total * (i + 1) / _segments).ceil();

  @override
  void didUpdateWidget(SeriesProgressBar old) {
    super.didUpdateWidget(old);
    if (old.total != widget.total || widget.read <= old.read || widget.total <= 0) {
      return;
    }
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return;
    _fresh = {
      for (var i = 0; i < _segments; i++)
        if (widget.read >= _end(i) && old.read < _end(i)) i,
    };
    _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.total;
    if (total <= 0) {
      return const SizedBox(height: SeriesProgressBar._height);
    }

    final segments = _segments;
    final currentIndex = widget.currentIndex;

    return Container(
      height: SeriesProgressBar._height,
      decoration: BoxDecoration(
        color: context.scheme.s2,
        borderRadius: BorderRadius.circular(AppTheme.r4),
      ),
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final animating = _c.isAnimating;
          final fill = Curves.easeOutBack
              .transform(const Interval(0, 0.7).transform(_c.value));
          final marker = Curves.easeOutBack
              .transform(const Interval(0.4, 1).transform(_c.value));

          return Row(
            children: List.generate(segments, (i) {
              // Issue-index boundaries for group i: [start, end), spread evenly
              // via ceil(total * k / segments) so every issue belongs to exactly
              // one group and group sizes differ by at most 1.
              final start = (total * i / segments).ceil();
              final end = _end(i);

              final isRead = widget.read >= end;
              final isCurrent = !isRead &&
                  currentIndex != null &&
                  currentIndex >= start &&
                  currentIndex < end;

              final color = isRead
                  ? AppTheme.green
                  : (isCurrent ? widget.accent : Colors.transparent);

              Widget seg = Container(
                key: ValueKey('progress-segment-$i'),
                height: SeriesProgressBar._height,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(AppTheme.r4),
                ),
              );
              if (animating && isRead && _fresh.contains(i)) {
                seg = Transform(
                  alignment: Alignment.centerLeft,
                  transform: Matrix4.diagonal3Values(fill.clamp(0.0, 1.2), 1, 1),
                  child: seg,
                );
              } else if (animating && isCurrent && _fresh.isNotEmpty) {
                seg = Transform.scale(scaleY: marker, child: seg);
              }

              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                      right: i == segments - 1 ? 0 : SeriesProgressBar._gap),
                  child: seg,
                ),
              );
            }),
          );
        },
      ),
    );
  }
}
