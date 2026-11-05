import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers.dart';

const _prefsKey = 'reader_rail_side';

/// Which side of the screen the reader's control rail sits on.
enum RailSide {
  left,
  right,
}

class RailSideNotifier extends Notifier<RailSide> {
  @override
  RailSide build() {
    final stored = ref.watch(sharedPrefsProvider).getString(_prefsKey);
    return RailSide.values
            .where((s) => s.name == stored)
            .firstOrNull ??
        RailSide.right;
  }

  void select(RailSide side) {
    state = side;
    ref.read(sharedPrefsProvider).setString(_prefsKey, side.name);
  }
}

final railSideProvider =
    NotifierProvider<RailSideNotifier, RailSide>(RailSideNotifier.new);
