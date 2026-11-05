import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers.dart';

const _prefsKey = 'reader_zone_peek';

/// Whether the tap-zone map flashes briefly each time a comic opens.
/// Device-local, like the rail side: it's about this device's grip.
class ZonePeekNotifier extends Notifier<bool> {
  @override
  bool build() => ref.watch(sharedPrefsProvider).getBool(_prefsKey) ?? true;

  void set(bool on) {
    state = on;
    ref.read(sharedPrefsProvider).setBool(_prefsKey, on);
  }
}

final zonePeekProvider =
    NotifierProvider<ZonePeekNotifier, bool>(ZonePeekNotifier.new);
