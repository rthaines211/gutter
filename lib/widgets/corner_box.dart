import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_theme.dart';
import '../config/comic_style.dart';
import '../config/scheme.dart';

/// A 1970s-style comic "corner box": a coloured title band, then a grid row
/// with one big figure on the left and a three-line stack on the right, then
/// optional art and footer rows.
///
/// Frame, rules and type follow Comic Style through [ComicTokens]: Off is a
/// clean card with hairlines and a soft shadow; Ink + Halftone adds ink rules
/// and the hard offset shadow; Full Pop also sets the band and big figure in
/// Bangers.
class CornerBox extends ConsumerWidget {
  final String band;

  /// Small mono text at the right end of the band (e.g. a serial number).
  final String? bandTrailing;

  /// Band fill. Text on it picks dark or white by contrast.
  final Color bandColor;

  final String big;
  final String? bigCaption;

  /// Right-hand stack, top to bottom. Usually three lines.
  final List<String> stack;

  final Widget? art;
  final Widget? footer;
  final Color accent;
  final double bigSize;

  /// Whether to draw the style's card shadow. Off when the box sits inside
  /// another frame (the reading stamp draws its own).
  final bool shadow;

  const CornerBox({
    super.key,
    required this.band,
    required this.bandColor,
    required this.big,
    required this.stack,
    required this.accent,
    this.bandTrailing,
    this.bigCaption,
    this.art,
    this.footer,
    this.bigSize = 38,
    this.shadow = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final comic = ComicTokens.watch(ref, context, accent);
    final scheme = context.scheme;
    final rule = BorderSide(color: comic.ink, width: comic.borderWidth);
    final onBand = Scheme.onAccent(bandColor);

    Widget hRule() => Container(height: comic.borderWidth, color: comic.ink);

    final bandText = AppTheme.displayTextStyle(comic, fontSize: 13).copyWith(
      color: onBand,
      height: 1,
      letterSpacing: comic.displayFont ? 1.2 : 0.8,
    );

    final stackStyle = AppTheme.monoCaption.copyWith(
      fontSize: 10.5,
      fontWeight: FontWeight.w700,
      color: scheme.tx,
      height: 1,
    );

    return Container(
      decoration: BoxDecoration(
        color: scheme.s1,
        borderRadius: BorderRadius.circular(3),
        border: Border.fromBorderSide(rule),
        boxShadow: shadow ? comic.cardShadow : const [],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: bandColor,
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 7),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      band.toUpperCase(),
                      style: bandText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (bandTrailing != null)
                    Text(
                      bandTrailing!,
                      style: AppTheme.monoCaption.copyWith(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: onBand.withValues(alpha: 0.85),
                      ),
                    ),
                ],
              ),
            ),
            hRule(),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(6, 10, 6, 9),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              big,
                              style: AppTheme.displayTextStyle(comic, fontSize: bigSize)
                                  .copyWith(color: scheme.tx, height: 1),
                            ),
                          ),
                          if (bigCaption != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              bigCaption!.toUpperCase(),
                              style: AppTheme.monoCaption.copyWith(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1,
                                color: scheme.t3,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  Container(width: comic.borderWidth, color: comic.ink),
                  Expanded(
                    child: Column(
                      children: [
                        for (var i = 0; i < stack.length; i++) ...[
                          if (i > 0) hRule(),
                          Expanded(
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(stack[i].toUpperCase(), style: stackStyle),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (art != null) ...[hRule(), art!],
            if (footer != null) ...[hRule(), footer!],
          ],
        ),
      ),
    );
  }
}

/// Run years for a series from its issues' cover dates ("1975–79", "1975",
/// "1998–2003"), falling back to the series start year. Null if unknown.
String? seriesRunYears(Iterable<int?> issueYears, {int? fallback}) {
  final years = issueYears.whereType<int>().where((y) => y > 1800).toList();
  if (years.isEmpty) return fallback?.toString();
  years.sort();
  final lo = years.first, hi = years.last;
  if (lo == hi) return '$lo';
  if (lo ~/ 100 == hi ~/ 100) return '$lo–${(hi % 100).toString().padLeft(2, '0')}';
  return '$lo–$hi';
}

/// Year from an ISO-ish cover date ("1979-05-01", "1979-05", "1979").
int? coverYear(String? coverDate) {
  if (coverDate == null || coverDate.length < 4) return null;
  return int.tryParse(coverDate.substring(0, 4));
}
