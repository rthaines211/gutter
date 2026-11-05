import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/flavor.dart';
import '../models/reader_settings.dart';
import '../services/api_client.dart';
import 'connectivity_provider.dart';
import 'providers.dart';

class SettingsNotifier extends AsyncNotifier<ReaderSettings> {
  late ApiClient _client;

  // Device copy of the settings, so offline (or a failed fetch) keeps the
  // reader's own fit/direction instead of snapping to defaults mid-issue.
  static const _cacheKey = 'reader_settings_cache';
  // Set when a save didn't reach the server: the next online build pushes
  // the device copy rather than letting the server's stale one undo it.
  static const _dirtyKey = 'reader_settings_dirty';
  // Store app: volume keys are opted into on this device. The Go backend's
  // default sends volume_keys: true for every new device, and App Review
  // 2.5.9 wants hardware-button hijacking off until the user turns it on.
  static const _volumeOptInKey = 'volume_keys_opt_in';

  @override
  Future<ReaderSettings> build() async {
    final s = await _load();
    if (!isStore) return s;
    final prefs = await SharedPreferences.getInstance();
    return s.copyWith(volumeKeys: prefs.getBool(_volumeOptInKey) ?? false);
  }

  Future<ReaderSettings> _load() async {
    _client = ref.watch(apiClientProvider);
    // read, not watch: a connectivity flip rebuilt this mid-read, and the
    // reader swapped itself for a spinner while it reloaded.
    final isOnline = ref.read(connectivityProvider);
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cacheKey);
    final cached = raw == null
        ? null
        : ReaderSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    if (!isOnline) return cached ?? const ReaderSettings();
    try {
      if (cached != null && (prefs.getBool(_dirtyKey) ?? false)) {
        await _client.updateSettings(cached);
        await prefs.setBool(_dirtyKey, false);
        return cached;
      }
      final fresh = await _client.getSettings();
      await prefs.setString(_cacheKey, jsonEncode(fresh.toJson()));
      return fresh;
    } catch (_) {
      return cached ?? const ReaderSettings();
    }
  }

  Future<void> save(ReaderSettings settings) async {
    state = AsyncData(settings);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cacheKey, jsonEncode(settings.toJson()));
    if (isStore) await prefs.setBool(_volumeOptInKey, settings.volumeKeys);
    try {
      await _client.updateSettings(settings);
      await prefs.setBool(_dirtyKey, false);
    } catch (_) {
      await prefs.setBool(_dirtyKey, true);
    }
  }
}

final settingsProvider =
    AsyncNotifierProvider<SettingsNotifier, ReaderSettings>(
  SettingsNotifier.new,
);
