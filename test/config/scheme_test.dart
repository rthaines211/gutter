// test/config/scheme_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/config/scheme.dart';

void main() {
  group('Scheme.oledBlack', () {
    test('matches the historical OLED values exactly', () {
      const s = Scheme.oledBlack;
      expect(s.bg, const Color(0xFF000000));
      expect(s.s1, const Color(0xFF131418));
      expect(s.s2, const Color(0xFF1C1E24));
      expect(s.s3, const Color(0xFF282A32));
      expect(s.tx, const Color(0xFFFFFFFF));
      expect(s.t2, const Color(0xB3EBEBF5));
      expect(s.t3, const Color(0x6BEBEBF5));
      expect(s.t4, const Color(0x38EBEBF5));
      expect(s.hair, const Color(0x14FFFFFF));
      expect(s.bgRaised, const Color(0xFF0A0A0C));
      expect(s.hairStrong, const Color(0x24FFFFFF));
      expect(s.borderFaint, const Color(0x0FFFFFFF));
    });

    test('keeps the three near-miss tokens distinct', () {
      // Regression guard: collapsing any of these onto `hair`/`bg` changes
      // the app's appearance and breaks the phase's identical-render rule.
      const s = Scheme.oledBlack;
      expect(s.hairStrong, isNot(s.hair));
      expect(s.borderFaint, isNot(s.hair));
      expect(s.bgRaised, isNot(s.bg));
    });

    test('is marked dark', () {
      expect(Scheme.oledBlack.dark, isTrue);
    });
  });

  group('Scheme.sepiaPaper', () {
    test('is a light scheme with the handoff paper values', () {
      const s = Scheme.sepiaPaper;
      expect(s.dark, isFalse);
      expect(s.bg, const Color(0xFFEFE4CC));
      expect(s.s1, const Color(0xFFF8F0DD));
      expect(s.tx, const Color(0xFF2A2116));
    });
  });

  group('lerp', () {
    test('returns the target scheme at t=1', () {
      final r = Scheme.oledBlack.lerp(Scheme.sepiaPaper, 1.0);
      expect(r.bg, Scheme.sepiaPaper.bg);
    });

    test('returns the source scheme at t=0', () {
      final r = Scheme.oledBlack.lerp(Scheme.sepiaPaper, 0.0);
      expect(r.bg, Scheme.oledBlack.bg);
    });
  });
}
