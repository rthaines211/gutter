import 'package:flutter/widgets.dart';

class LayoutBreakpoint {
  LayoutBreakpoint._();

  static const double tablet = 768.0;

  static bool isTablet(BuildContext context) {
    return MediaQuery.sizeOf(context).width >= tablet;
  }
}
