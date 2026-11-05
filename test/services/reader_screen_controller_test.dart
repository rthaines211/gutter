import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/services/reader_screen_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<String> calls;
  late bool hasChanged;

  setUp(() {
    calls = [];
    hasChanged = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('github.com/aaassseee/screen_brightness'),
            (call) async {
      calls.add(call.arguments == null
          ? call.method
          : '${call.method} ${(call.arguments as Map)['brightness']}');
      return switch (call.method) {
        'hasChanged' => hasChanged,
        'getScreenBrightness' => 0.7,
        _ => null,
      };
    });
  });

  bool set(String c) => c.startsWith('setScreenBrightness');
  bool reset(String c) => c == 'resetScreenBrightness';

  test('no override before: dim to 0, undo resets to system', () async {
    final c = ReaderScreenController();
    await c.dimForSleep();
    await c.undoSleepDim();
    expect(calls.where((x) => set(x) || reset(x)),
        ['setScreenBrightness 0.0', 'resetScreenBrightness']);
  });

  test('Aa override before: undo restores it', () async {
    hasChanged = true;
    final c = ReaderScreenController();
    await c.dimForSleep();
    await c.undoSleepDim();
    expect(calls.where(set), ['setScreenBrightness 0.0', 'setScreenBrightness 0.7']);
  });

  test('undo without dim does nothing', () async {
    await ReaderScreenController().undoSleepDim();
    expect(calls, isEmpty);
  });
}
