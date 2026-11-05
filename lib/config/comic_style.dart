import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'scheme.dart';
import '../providers/comic_style_provider.dart';

/// Global comic-book styling intensity. Drives every ink-outline, halftone,
/// hard-shadow, and display-font treatment app-wide via [ComicTokens] — no
/// screen should branch on this enum directly.
enum ComicStyle { off, inkHalftone, fullPop }

/// Derived styling tokens for the active [ComicStyle]. Widgets ask for a
/// token (a colour, a width, a shadow list, a bool flag) instead of
/// branching on [ComicStyle] themselves — see [ComicTokens.of].
@immutable
class ComicTokens {
  final Color ink;
  final double borderWidth;
  final List<BoxShadow> cardShadow;
  final bool pageDots;
  final bool benDay;
  final bool displayFont;
  final bool titleEffects;
  final bool captionBoxes;

  /// Whether [cardShadow] is a hard offset shadow that should replace a
  /// widget's own bespoke shadow treatment (true for inkHalftone/fullPop).
  /// False for `off`, where callers keep their pre-Phase-4 shadow instead —
  /// see `panel_frame.dart`'s `comic.hardShadow ? comic.cardShadow : _glassShadows()`.
  final bool hardShadow;

  const ComicTokens({
    required this.ink,
    required this.borderWidth,
    required this.cardShadow,
    required this.pageDots,
    required this.benDay,
    required this.displayFont,
    required this.titleEffects,
    required this.captionBoxes,
    required this.hardShadow,
  });

  /// Builds the tokens for [style] against [scheme], using [accent] for the
  /// hard shadow colour on dark schemes.
  ///
  /// There is deliberately no `context.comic` getter: a `BuildContext`
  /// extension has no `WidgetRef`, so it cannot read `comicStyleProvider`.
  /// Read in a ConsumerWidget/ConsumerState instead:
  ///   final comic = ComicTokens.of(ref.watch(comicStyleProvider), context.scheme, accent);
  /// or use the [watch] convenience below.
  factory ComicTokens.of(ComicStyle style, Scheme scheme, Color accent) {
    switch (style) {
      case ComicStyle.off:
        return ComicTokens(
          ink: scheme.hair,
          borderWidth: 0.5,
          cardShadow: [
            scheme.dark
                ? const BoxShadow(
                    color: Color(0x80000000),
                    offset: Offset(0, 14),
                    blurRadius: 32,
                  )
                : const BoxShadow(
                    color: Color(0x24000000),
                    offset: Offset(0, 8),
                    blurRadius: 24,
                  ),
          ],
          pageDots: false,
          benDay: false,
          displayFont: false,
          titleEffects: false,
          captionBoxes: false,
          hardShadow: false,
        );
      case ComicStyle.inkHalftone:
      case ComicStyle.fullPop:
        return ComicTokens(
          ink: scheme.ink,
          borderWidth: scheme.dark ? 1.5 : 2.0,
          cardShadow: [
            BoxShadow(
              color: scheme.dark ? accent : const Color(0xFF111111),
              offset: const Offset(4, 4),
              blurRadius: 0,
            ),
          ],
          pageDots: true,
          benDay: true,
          displayFont: style == ComicStyle.fullPop,
          titleEffects: style == ComicStyle.fullPop,
          captionBoxes: style == ComicStyle.fullPop,
          hardShadow: true,
        );
    }
  }

  /// Convenience for `ConsumerWidget`/`ConsumerState` call sites: reads the
  /// active style from `comicStyleProvider` and builds tokens in one line,
  /// e.g. `ComicTokens.watch(ref, context, accent)`. Widgets should call
  /// this instead of branching on `ComicStyle` themselves.
  static ComicTokens watch(WidgetRef ref, BuildContext context, Color accent) {
    return ComicTokens.of(ref.watch(comicStyleProvider), context.scheme, accent);
  }
}
