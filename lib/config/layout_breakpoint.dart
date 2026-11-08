import 'dart:ui' show DisplayFeatureState, DisplayFeatureType, PlatformDispatcher;

import 'package:flutter/widgets.dart';

import 'platform.dart';

class LayoutBreakpoint {
  LayoutBreakpoint._();

  static const double tablet = 768.0;

  static bool isTablet(BuildContext context) {
    return MediaQuery.sizeOf(context).width >= tablet;
  }

  /// The detail panel's share of a split view: 46% portrait, 40% landscape;
  /// on a foldable with a vertical hinge (or a half-open fold) the panel
  /// takes the side right of it, so neither pane straddles the crease.
  static double splitPanelFraction(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    for (final f in MediaQuery.displayFeaturesOf(context)) {
      final separates = f.type == DisplayFeatureType.hinge ||
          (f.type == DisplayFeatureType.fold &&
              f.state == DisplayFeatureState.postureHalfOpened);
      final vertical = f.bounds.height >= size.height - 1 &&
          f.bounds.width < size.width / 4;
      if (separates && vertical && size.width > 0) {
        return ((size.width - f.bounds.right) / size.width).clamp(0.3, 0.7);
      }
    }
    return MediaQuery.orientationOf(context) == Orientation.portrait ? 0.46 : 0.40;
  }

  /// "iPad" or "iPhone" for user-facing copy ("3 comics on this iPad");
  /// "tablet" or "phone" on Android. Uses the physical screen, so iPad split
  /// view still says iPad.
  static String get deviceNoun {
    final (tablet, phone) = isAndroid ? ('tablet', 'phone') : ('iPad', 'iPhone');
    final views = PlatformDispatcher.instance.views;
    if (views.isEmpty) return tablet;
    final d = views.first.display;
    // 700, not 600: the iPhone Duo's inner screen is 626pt; the smallest
    // iPad (mini) is 744pt. A foldable's outer screen is a phone, unfolded a
    // tablet: the display is the screen in use.
    return d.size.shortestSide / d.devicePixelRatio >= 700 ? tablet : phone;
  }
}
