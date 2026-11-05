import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:comic_reader_app/providers/grid_density_provider.dart';
import 'package:comic_reader_app/providers/providers.dart';
import 'package:comic_reader_app/widgets/sort_picker_sheet.dart';

Future<ProviderContainer> _container() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return ProviderContainer(
    overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('density picker shows the three options and the active one',
      (t) async {
    final c = await _container();
    addTearDown(c.dispose);
    await t.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: Scaffold(body: SortPickerSheet())),
    ));

    for (final label in ['Large', 'Medium', 'Small']) {
      expect(find.text(label), findsOneWidget);
    }
    // Default density is 4 == "Small".
    expect(c.read(gridDensityProvider), 4);
  });

  testWidgets('tapping a density option selects and persists it', (t) async {
    final c = await _container();
    addTearDown(c.dispose);
    await t.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: Scaffold(body: SortPickerSheet())),
    ));

    await t.tap(find.text('Large'));
    await t.pumpAndSettle();

    expect(c.read(gridDensityProvider), 2);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('grid_density'), 2,
        reason: 'the choice must survive a restart');
  });

  testWidgets('the sheet explains when A-Z grouping is active', (t) async {
    final c = await _container();
    addTearDown(c.dispose);
    await t.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: Scaffold(body: SortPickerSheet())),
    ));

    // Default filter is name/asc, so the library is sectioned.
    expect(find.textContaining('Grouped A–Z'), findsOneWidget);
  });
}
