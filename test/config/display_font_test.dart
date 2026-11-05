import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/config/app_theme.dart';
import 'package:comic_reader_app/config/comic_style.dart';
import 'package:comic_reader_app/config/scheme.dart';
import 'package:flutter/material.dart';

const _accent = Color(0xFF0A84FF);

void main() {
  test('fullPop uses Bangers with the handoff letter-spacing', () {
    final t = ComicTokens.of(ComicStyle.fullPop, Scheme.sepiaPaper, _accent);
    final s = AppTheme.displayTextStyle(t);
    expect(s.fontFamily, 'Bangers');
    expect(s.fontWeight, FontWeight.w400);
  });

  test('other styles keep the body face at weight 800', () {
    for (final style in [ComicStyle.off, ComicStyle.inkHalftone]) {
      final t = ComicTokens.of(style, Scheme.sepiaPaper, _accent);
      final s = AppTheme.displayTextStyle(t);
      expect(s.fontFamily, isNot('Bangers'));
      expect(s.fontWeight, FontWeight.w800);
    }
  });
}
