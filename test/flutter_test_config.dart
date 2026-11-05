import 'dart:async';

import 'package:comic_reader_app/config/flavor.dart';

/// `flutter test` passes no FLAVOR, which means store. Run the suite as the
/// personal app; store tests set `isStore = true` and reset it in tearDown.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  isStore = false;
  await testMain();
}
