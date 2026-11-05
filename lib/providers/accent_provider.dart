import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_theme.dart';

/// Load accent color from SharedPreferences.
Future<Color> loadAccentColor() async {
  final prefs = await SharedPreferences.getInstance();
  final preset = prefs.getString('accent_preset');

  if (preset == null) return AppTheme.accent;

  if (preset == 'custom') {
    final hex = prefs.getString('accent_custom_hex');
    if (hex != null && hex.length == 6) {
      final value = int.tryParse(hex, radix: 16);
      if (value != null) return Color(0xFF000000 | value);
    }
    return AppTheme.accent;
  }

  return AppTheme.accentPresets[preset] ?? AppTheme.accent;
}

/// Save a named preset.
Future<void> saveAccentPreset(String presetName) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('accent_preset', presetName);
}

/// Save a custom hex color.
Future<void> saveAccentCustom(Color color) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('accent_preset', 'custom');
  final hex = (color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();
  await prefs.setString('accent_custom_hex', hex);
}

class AccentNotifier extends AsyncNotifier<Color> {
  @override
  Future<Color> build() => loadAccentColor();

  Future<void> selectPreset(String presetName) async {
    final color = AppTheme.accentPresets[presetName] ?? AppTheme.accent;
    state = AsyncData(color);
    await saveAccentPreset(presetName);
  }

  Future<void> selectCustom(Color color) async {
    state = AsyncData(color);
    await saveAccentCustom(color);
  }
}

final accentProvider = AsyncNotifierProvider<AccentNotifier, Color>(
  AccentNotifier.new,
);
