import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:comic_reader_app/providers/accent_provider.dart';
import 'package:comic_reader_app/config/app_theme.dart';

void main() {
  group('AccentColor', () {
    test('defaults to electric blue when no preference saved', () async {
      SharedPreferences.setMockInitialValues({});
      final color = await loadAccentColor();
      expect(color, AppTheme.accent);
    });

    test('loads a preset by name', () async {
      SharedPreferences.setMockInitialValues({'accent_preset': 'comic-red'});
      final color = await loadAccentColor();
      expect(color, const Color(0xFFFF3B30));
    });

    test('loads a custom hex color', () async {
      SharedPreferences.setMockInitialValues({
        'accent_preset': 'custom',
        'accent_custom_hex': 'FF8800',
      });
      final color = await loadAccentColor();
      expect(color, const Color(0xFFFF8800));
    });

    test('falls back to default for unknown preset', () async {
      SharedPreferences.setMockInitialValues({
        'accent_preset': 'nonexistent',
      });
      final color = await loadAccentColor();
      expect(color, AppTheme.accent);
    });

    test('saveAccentPreset persists preset name', () async {
      SharedPreferences.setMockInitialValues({});
      await saveAccentPreset('violet');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('accent_preset'), 'violet');
    });

    test('saveAccentCustom persists hex and sets preset to custom', () async {
      SharedPreferences.setMockInitialValues({});
      await saveAccentCustom(const Color(0xFFAABBCC));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('accent_preset'), 'custom');
      expect(prefs.getString('accent_custom_hex'), 'AABBCC');
    });
  });
}
