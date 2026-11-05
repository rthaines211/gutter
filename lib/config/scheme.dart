import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Runtime theme tokens. Field names match the design handoff's scheme table.
@immutable
class Scheme extends ThemeExtension<Scheme> {
  final Color bg, bgRaised, s1, s2, s3;
  final Color tx, t2, t3, t4;
  final Color hair, hairStrong, borderFaint;

  /// Translucent bar fill and comic-style outline colour.
  ///
  /// Values come from the design handoff's scheme table. `ink` is unread
  /// until Phase 4.
  final Color glass, ink;

  /// Wash behind a modal or over cover art.
  final Color scrim;

  final bool dark;

  /// Whether the scheme paints a global halftone dot texture. Unread in
  /// Phase 1; Phase 4 consumes it.
  final bool dots;

  const Scheme({
    required this.bg,
    required this.bgRaised,
    required this.s1,
    required this.s2,
    required this.s3,
    required this.tx,
    required this.t2,
    required this.t3,
    required this.t4,
    required this.hair,
    required this.hairStrong,
    required this.borderFaint,
    required this.glass,
    required this.ink,
    required this.scrim,
    required this.dark,
    required this.dots,
  });

  /// Ink colour for text/icons sitting ON an accent fill. The accent is
  /// user-selectable (see `AppTheme.accentPresets`) and lives outside
  /// `Scheme`, so this is a function of the accent, not a scheme field.
  ///
  /// Picks whichever of dark/white actually contrasts more against the given
  /// accent, rather than testing luminance against a fixed threshold. The
  /// design handoff specifies "#111 if accent luminance > .62", but that
  /// threshold was authored for its own four swatches and misjudges this app's
  /// palette badly: amber (#FFB800) sits at luminance .555, so a .62 threshold
  /// hands it white ink at 1.73:1 — unreadable — where dark ink gives 10.89:1.
  /// Relative luminance is green-weighted, so the threshold is a proxy that
  /// drifts on saturated hues; comparing the two contrast ratios directly
  /// computes what the threshold was approximating, gets every preset right,
  /// and needs no tuning when a new accent is added.
  static Color onAccent(Color accent) {
    const dark = Color(0xFF111111);
    const light = Color(0xFFFFFFFF);
    return _contrast(dark, accent) >= _contrast(light, accent) ? dark : light;
  }

  /// WCAG 2.1 contrast ratio between two opaque colours.
  static double _contrast(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final hi = la > lb ? la : lb;
    final lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }

  static const oledBlack = Scheme(
    bg: Color(0xFF000000),
    bgRaised: Color(0xFF0A0A0C),
    s1: Color(0xFF131418),
    s2: Color(0xFF1C1E24),
    s3: Color(0xFF282A32),
    tx: Color(0xFFFFFFFF),
    t2: Color(0xB3EBEBF5),
    t3: Color(0x6BEBEBF5),
    t4: Color(0x38EBEBF5),
    hair: Color(0x14FFFFFF),
    hairStrong: Color(0x24FFFFFF),
    borderFaint: Color(0x0FFFFFFF),
    glass: Color(0x9E141519),
    ink: Color(0xFFFFFFFF),
    scrim: Color(0x80000000),
    dark: true,
    dots: false,
  );

  static const sepiaPaper = Scheme(
    bg: Color(0xFFEFE4CC),
    bgRaised: Color(0xFFF3EAD4),
    s1: Color(0xFFF8F0DD),
    s2: Color(0xFFE6D9BC),
    s3: Color(0xFFD5C5A2),
    tx: Color(0xFF2A2116),
    t2: Color(0xB82A2116),
    t3: Color(0x802A2116),
    t4: Color(0x4D2A2116),
    hair: Color(0x242A2116),
    hairStrong: Color(0x3F2A2116),
    borderFaint: Color(0x192A2116),
    glass: Color(0xC7F8F0DD),
    ink: Color(0xFF111111),
    scrim: Color(0x40000000),
    dark: false,
    dots: false,
  );

  @override
  Scheme copyWith({
    Color? bg, Color? bgRaised, Color? s1, Color? s2, Color? s3,
    Color? tx, Color? t2, Color? t3, Color? t4,
    Color? hair, Color? hairStrong, Color? borderFaint,
    Color? glass, Color? ink,
    Color? scrim,
    bool? dark, bool? dots,
  }) {
    return Scheme(
      bg: bg ?? this.bg,
      bgRaised: bgRaised ?? this.bgRaised,
      s1: s1 ?? this.s1,
      s2: s2 ?? this.s2,
      s3: s3 ?? this.s3,
      tx: tx ?? this.tx,
      t2: t2 ?? this.t2,
      t3: t3 ?? this.t3,
      t4: t4 ?? this.t4,
      hair: hair ?? this.hair,
      hairStrong: hairStrong ?? this.hairStrong,
      borderFaint: borderFaint ?? this.borderFaint,
      glass: glass ?? this.glass,
      ink: ink ?? this.ink,
      scrim: scrim ?? this.scrim,
      dark: dark ?? this.dark,
      dots: dots ?? this.dots,
    );
  }

  @override
  Scheme lerp(ThemeExtension<Scheme>? other, double t) {
    if (other is! Scheme) return this;
    return Scheme(
      bg: Color.lerp(bg, other.bg, t)!,
      bgRaised: Color.lerp(bgRaised, other.bgRaised, t)!,
      s1: Color.lerp(s1, other.s1, t)!,
      s2: Color.lerp(s2, other.s2, t)!,
      s3: Color.lerp(s3, other.s3, t)!,
      tx: Color.lerp(tx, other.tx, t)!,
      t2: Color.lerp(t2, other.t2, t)!,
      t3: Color.lerp(t3, other.t3, t)!,
      t4: Color.lerp(t4, other.t4, t)!,
      hair: Color.lerp(hair, other.hair, t)!,
      hairStrong: Color.lerp(hairStrong, other.hairStrong, t)!,
      borderFaint: Color.lerp(borderFaint, other.borderFaint, t)!,
      glass: Color.lerp(glass, other.glass, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      scrim: Color.lerp(scrim, other.scrim, t)!,
      dark: t < 0.5 ? dark : other.dark,
      dots: t < 0.5 ? dots : other.dots,
    );
  }
}

/// Scheme-aware text styles.
///
/// `AppTheme`'s static styles carry no colour so they can work in any scheme.
/// Primary text inherits the right colour from `ThemeData.textTheme`, but
/// captions and section headers are meant to be DIMMER than body text, which
/// inheritance cannot express. These getters resolve them against the active
/// scheme: `context.monoCaption` instead of `context.monoCaption`.
extension SchemeTextStyles on BuildContext {
  /// Mono caption, dimmed to tertiary text.
  TextStyle get monoCaption => AppTheme.monoCaption.copyWith(color: scheme.t3);

  /// Mono label, dimmed to tertiary text.
  TextStyle get monoLabel => AppTheme.monoLabel.copyWith(color: scheme.t3);

  /// Uppercase section header, dimmed to tertiary text.
  TextStyle get sectionHeader =>
      AppTheme.sectionHeader.copyWith(color: scheme.t3);
}

/// Read the active scheme: `context.scheme.tx`.
extension SchemeContext on BuildContext {
  Scheme get scheme =>
      Theme.of(this).extension<Scheme>() ?? Scheme.oledBlack;
}
