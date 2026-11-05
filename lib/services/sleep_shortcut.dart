import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The Shortcut the sleep timer runs when it fires. iOS gives apps no way
/// to turn on Focus / Do Not Disturb; a user-built Shortcut can.
const kSleepShortcutName = 'Comic Sleep';

/// "Run the shortcut" toggle. Device-local (SharedPreferences), not a
/// server reader setting: whether the Shortcut exists is per device.
class SleepShortcutNotifier extends AsyncNotifier<bool> {
  static const _key = 'sleep_run_shortcut';

  @override
  Future<bool> build() async =>
      (await SharedPreferences.getInstance()).getBool(_key) ?? false;

  Future<void> set(bool on) async {
    state = AsyncData(on);
    await (await SharedPreferences.getInstance()).setBool(_key, on);
  }
}

final sleepShortcutProvider =
    AsyncNotifierProvider<SleepShortcutNotifier, bool>(SleepShortcutNotifier.new);

/// iCloud copy of the Shortcut (Do Not Disturb on, then Lock Screen), so
/// setup is one tap on Add.
const kSleepShortcutLink =
    'https://www.icloud.com/shortcuts/3cb33b79b7c34b9b8a3a907d74861399';

const _openUrl = MethodChannel('app.comic_reader/open_url');

/// Opens the Shortcut's Add page in the Shortcuts app.
Future<void> addSleepShortcut() async {
  try {
    await _openUrl.invokeMethod('open', kSleepShortcutLink);
  } catch (_) {}
}

/// Hands off to the Shortcuts app. It comes to the front and stays there:
/// the app has no URL scheme for an x-success return, and at bedtime that
/// does not matter.
Future<void> runSleepShortcut() async {
  try {
    await _openUrl.invokeMethod('open',
        'shortcuts://run-shortcut?name=${Uri.encodeComponent(kSleepShortcutName)}');
  } catch (_) {}
}
