import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

/// True on Android. Read this, not `Platform.isAndroid`, so tests can flip it
/// (like `isStore`; only tests assign it). `flutter test` runs on the host,
/// so the suite sees false: the iOS behaviour.
bool isAndroid = !kIsWeb && Platform.isAndroid;

/// Whether panels can be found on the device (the Core ML model behind the
/// `app.comic_reader/panels` channel, iOS only). Off on Android until the
/// model is ported; sources without server sidecars then offer no Panels zoom.
bool get onDevicePanels => !isAndroid;

/// The store the Pro unlock is bought from, for user-facing copy.
String get storeName => isAndroid ? 'Google Play' : 'the App Store';
