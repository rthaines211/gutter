import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/config/app_theme.dart';
import 'package:comic_reader_app/config/scheme.dart';

void main() {
  group('light scheme legibility', () {
    test('sepia text tokens are dark enough to read on its surfaces', () {
      const s = Scheme.sepiaPaper;
      // Primary text on the base background must clear WCAG AA (4.5:1).
      expect(_contrast(s.tx, s.bg), greaterThan(4.5));
      // Secondary text on cards must clear AA for large text (3:1).
      expect(_contrast(s.t2, s.s1), greaterThan(3.0));
    });

    test('dark scheme still clears the same bars', () {
      const s = Scheme.oledBlack;
      expect(_contrast(s.tx, s.bg), greaterThan(4.5));
      expect(_contrast(s.t2, s.s1), greaterThan(3.0));
    });

    test('every scheme marks its own brightness correctly', () {
      expect(Scheme.oledBlack.dark, isTrue);
      expect(Scheme.sepiaPaper.dark, isFalse);
      // A scheme's bg must actually match its `dark` claim.
      expect(_luminance(Scheme.oledBlack.bg), lessThan(0.5));
      expect(_luminance(Scheme.sepiaPaper.bg), greaterThan(0.5));
    });
  });

  group('new tokens', () {
    test('scrim is lighter in the light scheme', () {
      expect(Scheme.sepiaPaper.scrim.a, lessThan(Scheme.oledBlack.scrim.a));
    });

    test('ink is the outline colour, fully opaque in both schemes', () {
      expect(Scheme.oledBlack.ink, const Color(0xFFFFFFFF));
      expect(Scheme.sepiaPaper.ink, const Color(0xFF111111));
    });
  });

  group('lerp covers the new fields', () {
    test('scrim interpolates to the target', () {
      final r = Scheme.oledBlack.lerp(Scheme.sepiaPaper, 1.0);
      expect(r.scrim, Scheme.sepiaPaper.scrim);
    });
  });

  group('Scheme.onAccent — accent-derived ink', () {
    // onAccent picks whichever of dark/white actually contrasts more against
    // the accent, rather than testing luminance against a fixed threshold.
    // The handoff's ".62 luminance" rule was authored for its own four
    // swatches and misjudges this palette: amber sits at .555, so a .62
    // threshold would hand it white ink at 1.73:1 — unreadable.
    // Expectations below are the measured better choice for each preset.
    const white = Color(0xFFFFFFFF);
    const dark = Color(0xFF111111);

    const expected = <String, Color>{
      'electric': dark,   // white 3.65 vs dark 5.18
      'comic-red': dark,  // white 3.55 vs dark 5.32
      'violet': dark,     // white 3.52 vs dark 5.36
      'amber': dark,      // white 1.73 vs dark 10.89 — the critical one
      'green': dark,      // white 2.02 vs dark 9.34
      'cobalt': white,    // white 8.44 vs dark 2.24
      'navy': white,      // white 10.36 vs dark 1.82
    };

    for (final entry in expected.entries) {
      test('${entry.key} selects the higher-contrast ink', () {
        final accent = AppTheme.accentPresets[entry.key]!;
        expect(Scheme.onAccent(accent), entry.value);
      });
    }

    test('every preset clears 4.5:1 with the ink onAccent picks', () {
      // The real guarantee: whatever ink is chosen must be readable. This is
      // what would catch a new accent preset being added with a bad pairing.
      for (final entry in AppTheme.accentPresets.entries) {
        final ratio = _contrast(Scheme.onAccent(entry.value), entry.value);
        expect(ratio, greaterThan(4.5),
            reason: '${entry.key} only reaches ${ratio.toStringAsFixed(2)}:1');
      }
    });

    test('picks dark ink on a light accent and white on a dark one', () {
      expect(Scheme.onAccent(const Color(0xFFFFFFFF)), dark);
      expect(Scheme.onAccent(const Color(0xFF000000)), white);
    });
  });
}

/// Relative luminance per WCAG 2.1.
double _luminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

/// Contrast ratio between two colours, flattening any alpha in [fg] over [bg]
/// first — the scheme's text tokens are alpha-based, so comparing them
/// directly would overstate their contrast.
double _contrast(Color fg, Color bg) {
  final a = fg.a;
  final flat = Color.from(
    alpha: 1.0,
    red: fg.r * a + bg.r * (1 - a),
    green: fg.g * a + bg.g * (1 - a),
    blue: fg.b * a + bg.b * (1 - a),
  );
  final l1 = _luminance(flat);
  final l2 = _luminance(bg);
  final hi = l1 > l2 ? l1 : l2;
  final lo = l1 > l2 ? l2 : l1;
  return (hi + 0.05) / (lo + 0.05);
}
