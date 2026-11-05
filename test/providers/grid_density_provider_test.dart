import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:comic_reader_app/providers/grid_density_provider.dart';
import 'package:comic_reader_app/providers/providers.dart';

Future<ProviderContainer> makeContainer(Map<String, Object> initial) async {
  SharedPreferences.setMockInitialValues(initial);
  final prefs = await SharedPreferences.getInstance();
  return ProviderContainer(
    overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('defaults to 4 columns', () async {
    final c = await makeContainer({});
    expect(c.read(gridDensityProvider), 4);
  });

  test('restores a stored density', () async {
    final c = await makeContainer({'grid_density': 2});
    expect(c.read(gridDensityProvider), 2);
  });

  test('rejects an out-of-range stored value', () async {
    final c = await makeContainer({'grid_density': 9});
    expect(c.read(gridDensityProvider), 4);
  });

  test('select updates state and persists', () async {
    final c = await makeContainer({});
    c.read(gridDensityProvider.notifier).select(3);
    expect(c.read(gridDensityProvider), 3);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('grid_density'), 3);
  });

  test('select ignores an invalid value', () async {
    final c = await makeContainer({});
    c.read(gridDensityProvider.notifier).select(7);
    expect(c.read(gridDensityProvider), 4);
  });

  group('libraryColumns', () {
    test('phone uses the density directly', () {
      expect(columnsForWidth(390, density: 3, tablet: false), 3);
      expect(columnsForWidth(390, density: 2, tablet: false), 2);
    });

    test('tablet divides width by the density target', () {
      // density 4 -> target 120
      expect(columnsForWidth(1024, density: 4, tablet: true), 9);
      // density 2 -> target 190
      expect(columnsForWidth(760, density: 2, tablet: true), 4);
    });

    test('tablet never goes below 2 columns', () {
      expect(columnsForWidth(200, density: 2, tablet: true), 2);
    });
  });
}
