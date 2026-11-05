import 'package:screen_brightness/screen_brightness.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class ReaderScreenController {
  ReaderScreenController();

  bool _sleepDimmed = false;

  /// App brightness override in place before [dimForSleep]; null means
  /// there was none and undoing the dim resets to the system level.
  double? _beforeDim;

  void setKeepScreenOn(bool enabled) {
    if (enabled) {
      WakelockPlus.enable();
    } else {
      WakelockPlus.disable();
    }
  }

  /// Sleep timer fired: lowest brightness until [undoSleepDim].
  Future<void> dimForSleep() async {
    if (_sleepDimmed) return;
    _sleepDimmed = true;
    try {
      final b = ScreenBrightness.instance;
      _beforeDim = await b.hasChanged ? await b.current : null;
      await b.setScreenBrightness(0);
    } catch (_) {}
  }

  /// Puts brightness back the way it was before [dimForSleep] (the Aa
  /// slider's value, or the system level). No-op if not dimmed.
  Future<void> undoSleepDim() async {
    if (!_sleepDimmed) return;
    _sleepDimmed = false;
    try {
      final before = _beforeDim;
      if (before == null) {
        await ScreenBrightness.instance.resetScreenBrightness();
      } else {
        await ScreenBrightness.instance.setScreenBrightness(before);
      }
    } catch (_) {}
  }

  void dispose() {
    WakelockPlus.disable();
    try {
      ScreenBrightness.instance.resetScreenBrightness();
    } catch (_) {}
  }
}
