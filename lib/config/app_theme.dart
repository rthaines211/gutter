import 'package:flutter/material.dart';
import 'scheme.dart';
import 'comic_style.dart';

class AppTheme {
  AppTheme._();

  // Semantic colors
  static const green = Color(0xFF30D158);
  static const amber = Color(0xFFFFB800);
  static const blue = Color(0xFF0A84FF);
  static const violet = Color(0xFFBF5AF2);

  // Default accent (Electric Blue) — used as fallback only
  static const accent = Color(0xFF0A84FF);
  static const accentDim = Color(0xFF0862BE);

  // Accent presets — selectable by user
  static const Map<String, Color> accentPresets = {
    'electric': Color(0xFF0A84FF),
    'comic-red': Color(0xFFFF3B30),
    'violet': Color(0xFFBF5AF2),
    'amber': Color(0xFFFFB800),
    'green': Color(0xFF30D158),
    'cobalt': Color(0xFF0047AB),
    'navy': Color(0xFF1E3A8A),
  };

  /// Accent at 55% opacity — for glow effects
  static Color accentGlow(Color accent) => accent.withValues(alpha: 0.55);

  /// Accent at 14% opacity — for tinted backgrounds
  static Color accentSoft(Color accent) => accent.withValues(alpha: 0.14);

  // Radii
  static const double r4 = 4;
  static const double r8 = 8;
  static const double r12 = 12;
  static const double r14 = 14;
  static const double r16 = 16;
  static const double r18 = 18;
  static const double r20 = 20;
  static const double r24 = 24;
  static const double r28 = 28;
  static const double r30 = 30;
  static const double r32 = 32;
  static const double r40 = 40;
  static const double pill = 999;

  // Common text styles.
  //
  // These deliberately carry NO colour. They inherit from the ambient
  // DefaultTextStyle, which themeData() binds to the active Scheme below, so
  // one style works in every scheme. Hardcoding a colour here made every one
  // of the ~79 call sites invisible on a light background.
  static const TextStyle titleLarge = TextStyle(
    fontSize: 34,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.8,
    height: 1.05,
  );

  static const TextStyle titleMedium = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.4,
  );

  static const TextStyle monoCaption = TextStyle(
    fontSize: 12,
    fontFamily: '.SF Mono',
    fontFamilyFallback: ['JetBrains Mono', 'monospace'],
    letterSpacing: 0.5,
  );

  static const TextStyle monoLabel = TextStyle(
    fontSize: 13,
    fontFamily: '.SF Mono',
    fontFamilyFallback: ['JetBrains Mono', 'monospace'],
    letterSpacing: 0.5,
  );

  static const TextStyle sectionHeader = TextStyle(
    fontSize: 12,
    fontFamily: '.SF Mono',
    fontFamilyFallback: ['JetBrains Mono', 'monospace'],
    fontWeight: FontWeight.w700,
    letterSpacing: 0.8,
  );

  /// Comic-book display face for H1/H2/hero/series-title/letter-header text.
  ///
  /// Colourless like the styles above — inherits from the active scheme.
  /// `fontSize` defaults to [titleLarge]'s 34 (the common display size) so
  /// the handoff's `.03em` letter-spacing (`0.03 * fontSize`) has a sensible
  /// value even when the caller doesn't override it; pass the actual size
  /// at smaller call sites (e.g. section H2) for a precise result.
  static TextStyle displayTextStyle(ComicTokens comic, {double fontSize = 34}) {
    if (comic.displayFont) {
      return TextStyle(
        fontFamily: 'Bangers',
        fontWeight: FontWeight.w400,
        fontSize: fontSize,
        letterSpacing: fontSize * 0.03,
      );
    }
    return TextStyle(fontWeight: FontWeight.w800, fontSize: fontSize);
  }

  static ThemeData themeData(Scheme scheme) {
    return (scheme.dark ? ThemeData.dark() : ThemeData.light()).copyWith(
      scaffoldBackgroundColor: scheme.bg,
      colorScheme: (scheme.dark
              ? const ColorScheme.dark()
              : const ColorScheme.light())
          .copyWith(
        primary: accent,
        secondary: accent,
        surface: scheme.s1,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: scheme.tx,
        elevation: 0,
      ),
      // Colourless static styles (and any uncoloured Text) inherit from here,
      // so text follows the scheme instead of ThemeData's own defaults.
      textTheme: (scheme.dark ? ThemeData.dark() : ThemeData.light())
          .textTheme
          .apply(bodyColor: scheme.tx, displayColor: scheme.tx),
      extensions: [scheme],
    );
  }
}
