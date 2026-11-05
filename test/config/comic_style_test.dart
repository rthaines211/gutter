import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/config/comic_style.dart';
import 'package:comic_reader_app/config/scheme.dart';

const _accent = Color(0xFF0A84FF);

void main() {
  group("off — must reproduce today's look", () {
    test('uses the scheme hairline, not ink', () {
      final t = ComicTokens.of(ComicStyle.off, Scheme.sepiaPaper, _accent);
      expect(t.ink, Scheme.sepiaPaper.hair);
      expect(t.borderWidth, 0.5);
    });

    test('has a soft blurred shadow, not a hard offset one', () {
      final t = ComicTokens.of(ComicStyle.off, Scheme.sepiaPaper, _accent);
      expect(t.cardShadow.single.blurRadius, greaterThan(0));
    });

    test('turns every comic treatment off', () {
      final t = ComicTokens.of(ComicStyle.off, Scheme.sepiaPaper, _accent);
      expect(t.pageDots, isFalse);
      expect(t.benDay, isFalse);
      expect(t.displayFont, isFalse);
      expect(t.titleEffects, isFalse);
      expect(t.captionBoxes, isFalse);
    });
  });

  group('inkHalftone', () {
    test('uses the scheme ink and a hard shadow', () {
      final t = ComicTokens.of(ComicStyle.inkHalftone, Scheme.sepiaPaper, _accent);
      expect(t.ink, Scheme.sepiaPaper.ink);
      expect(t.cardShadow.single.blurRadius, 0);
      expect(t.cardShadow.single.offset, const Offset(4, 4));
    });

    test('hard shadow is ink on a light scheme, accent on a dark one', () {
      final light = ComicTokens.of(ComicStyle.inkHalftone, Scheme.sepiaPaper, _accent);
      final dark = ComicTokens.of(ComicStyle.inkHalftone, Scheme.oledBlack, _accent);
      expect(light.cardShadow.single.color, const Color(0xFF111111));
      expect(dark.cardShadow.single.color, _accent);
    });

    test('border is wider on light schemes', () {
      final light = ComicTokens.of(ComicStyle.inkHalftone, Scheme.sepiaPaper, _accent);
      final dark = ComicTokens.of(ComicStyle.inkHalftone, Scheme.oledBlack, _accent);
      expect(light.borderWidth, 2.0);
      expect(dark.borderWidth, 1.5);
    });

    test('enables texture but NOT the display font or caption boxes', () {
      final t = ComicTokens.of(ComicStyle.inkHalftone, Scheme.sepiaPaper, _accent);
      expect(t.pageDots, isTrue);
      expect(t.benDay, isTrue);
      expect(t.displayFont, isFalse);
      expect(t.captionBoxes, isFalse);
    });
  });

  group('fullPop', () {
    test('adds the display font, title effects and caption boxes', () {
      final t = ComicTokens.of(ComicStyle.fullPop, Scheme.sepiaPaper, _accent);
      expect(t.displayFont, isTrue);
      expect(t.titleEffects, isTrue);
      expect(t.captionBoxes, isTrue);
    });

    test("keeps inkHalftone's borders and shadows", () {
      final full = ComicTokens.of(ComicStyle.fullPop, Scheme.sepiaPaper, _accent);
      final ink = ComicTokens.of(ComicStyle.inkHalftone, Scheme.sepiaPaper, _accent);
      expect(full.ink, ink.ink);
      expect(full.borderWidth, ink.borderWidth);
      expect(full.cardShadow.single.offset, ink.cardShadow.single.offset);
    });
  });
}
