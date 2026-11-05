// lib/providers/grid_density_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers.dart';

const _prefsKey = 'grid_density';
const _valid = {2, 3, 4};
const _default = 4;

/// Tile width targets on a tablet, by density. Wider target = fewer columns.
const _tabletTarget = {2: 190.0, 3: 150.0, 4: 120.0};

class GridDensityNotifier extends Notifier<int> {
  @override
  int build() {
    final stored = ref.watch(sharedPrefsProvider).getInt(_prefsKey);
    return _valid.contains(stored) ? stored! : _default;
  }

  void select(int columns) {
    if (!_valid.contains(columns)) return;
    state = columns;
    ref.read(sharedPrefsProvider).setInt(_prefsKey, columns);
  }
}

final gridDensityProvider =
    NotifierProvider<GridDensityNotifier, int>(GridDensityNotifier.new);

/// Columns to render for a viewport width.
///
/// A phone shows exactly the chosen density. A tablet is much wider, so the
/// density picks a target tile width and the column count follows from it —
/// otherwise 4 columns on an iPad would be enormous tiles.
int columnsForWidth(double width, {required int density, required bool tablet}) {
  if (!tablet) return density;
  final target = _tabletTarget[density] ?? _tabletTarget[_default]!;
  final n = (width / target).round();
  return n < 2 ? 2 : n;
}
