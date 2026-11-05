import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/config/flavor.dart';

void main() {
  tearDown(() => isStore = false);

  test('tests run as the personal app by default', () {
    // flutter_test_config.dart pins it; otherwise `flutter test` (no FLAVOR)
    // would run the whole suite as the store app.
    expect(isStore, isFalse);
  });

  test('appName follows the flavor', () {
    expect(appName, 'Longbox');
    isStore = true;
    expect(appName, 'Gutter');
  });
}
