import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/widgets.dart';

class LayoutBreakpoint {
  LayoutBreakpoint._();

  static const double tablet = 768.0;

  static bool isTablet(BuildContext context) {
    return MediaQuery.sizeOf(context).width >= tablet;
  }

  /// "iPad" or "iPhone" for user-facing copy ("3 comics on this iPad").
  /// Uses the physical screen, so iPad split view still says iPad.
  static String get deviceNoun {
    final views = PlatformDispatcher.instance.views;
    if (views.isEmpty) return 'iPad';
    final d = views.first.display;
    return d.size.shortestSide / d.devicePixelRatio >= 600 ? 'iPad' : 'iPhone';
  }
}
