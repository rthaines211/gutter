import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_theme.dart';
import '../config/comic_style.dart';
import '../config/scheme.dart';
import '../models/stats_summary.dart';
import 'corner_box.dart';
import 'longbox_mark.dart';

/// This month's reading as a collectible stamp: a perforated card in the
/// corner-box trade dress. Pages read take the big slot; month, year and
/// issues finished take the stack; the Longbox mark sits on an accent dot.
///
/// Uses only figures the stats summary scopes to the month (pages, issues,
/// time read) plus the current streak, so nothing all-time is passed off as
/// monthly.
class ReadingStamp extends ConsumerWidget {
  final StatsSummary summary;
  final Color accent;
  final DateTime month;

  const ReadingStamp({
    super.key,
    required this.summary,
    required this.accent,
    required this.month,
  });

  static const _months = [
    'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
    'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
  ];

  static String groupThousands(int n) {
    final s = n.toString();
    final out = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) out.write(',');
      out.write(s[i]);
    }
    return out.toString();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final comic = ComicTokens.watch(ref, context, accent);
    final scheme = context.scheme;
    final m = summary.thisMonth;
    final issues = m.issuesFinished;
    final spine = scheme.dark ? const Color(0xFFF8F0DD) : scheme.tx;

    final footStyle = AppTheme.monoCaption.copyWith(
      fontSize: 9.5,
      fontWeight: FontWeight.w700,
      color: scheme.t2,
      letterSpacing: 0.4,
    );
    TextSpan footItem(String label, String value) => TextSpan(children: [
          TextSpan(text: '$label '),
          TextSpan(text: value, style: TextStyle(color: scheme.tx)),
        ]);

    return Semantics(
      label: '${_months[month.month - 1]} ${month.year} reading stamp: '
          '${m.pagesRead} pages, $issues issues finished',
      child: CustomPaint(
        painter: _PerforatedPainter(
          color: scheme.s1,
          softShadow: comic.hardShadow ? null : const Color(0x66000000),
          hardShadow: comic.hardShadow ? comic.cardShadow.first.color : null,
        ),
        child: Padding(
          padding: const EdgeInsets.all(11),
          child: CornerBox(
            band: 'Longbox Reading Stamp',
            bandTrailing: 'No. ${month.month}',
            bandColor: accent,
            big: groupThousands(m.pagesRead),
            bigCaption: 'Pages',
            bigSize: 40,
            stack: [
              _months[month.month - 1],
              '${month.year}',
              '$issues ${issues == 1 ? 'issue' : 'issues'}',
            ],
            accent: accent,
            shadow: false,
            art: SizedBox(
              height: 150,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 118,
                    height: 118,
                    decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                  ),
                  LongboxMark(size: 104, accent: accent, spineColor: spine),
                ],
              ),
            ),
            footer: Padding(
              padding: const EdgeInsets.fromLTRB(9, 8, 9, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text.rich(footItem('TIME', m.formattedTime), style: footStyle),
                  Text.rich(
                    footItem('STREAK', '${summary.streak.current}d'),
                    style: footStyle,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Stamp paper: a card whose edges are punched with half circles, so the
/// page shows through as perforations. Casts the style's shadow: soft for
/// Off, a hard 4px offset copy of the shape for Ink + Halftone / Full Pop.
class _PerforatedPainter extends CustomPainter {
  final Color color;
  final Color? softShadow;
  final Color? hardShadow;

  const _PerforatedPainter({required this.color, this.softShadow, this.hardShadow});

  static const _r = 3.4;
  static const _pitch = 12.0;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paper = Path()..addRect(rect);
    final holes = Path();
    for (double x = _pitch / 2; x < size.width; x += _pitch) {
      holes.addOval(Rect.fromCircle(center: Offset(x, 0), radius: _r));
      holes.addOval(Rect.fromCircle(center: Offset(x, size.height), radius: _r));
    }
    for (double y = _pitch / 2; y < size.height; y += _pitch) {
      holes.addOval(Rect.fromCircle(center: Offset(0, y), radius: _r));
      holes.addOval(Rect.fromCircle(center: Offset(size.width, y), radius: _r));
    }
    final shape = Path.combine(PathOperation.difference, paper, holes);
    if (softShadow != null) canvas.drawShadow(shape, softShadow!, 10, false);
    if (hardShadow != null) {
      canvas.drawPath(shape.shift(const Offset(4, 4)), Paint()..color = hardShadow!);
    }
    canvas.drawPath(shape, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_PerforatedPainter old) =>
      old.color != color ||
      old.softShadow != softShadow ||
      old.hardShadow != hardShadow;
}
