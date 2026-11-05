import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:comic_reader_app/providers/library_mode_provider.dart';
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

  test('defaults to sectioned', () async {
    final c = await makeContainer({});
    expect(c.read(libraryModeProvider), LibraryMode.sectioned);
  });

  test('restores a stored mode', () async {
    final c = await makeContainer({'library_mode': 'publisher'});
    expect(c.read(libraryModeProvider), LibraryMode.publisher);
  });

  test('falls back to sectioned on an unrecognised stored value', () async {
    final c = await makeContainer({'library_mode': 'by-colour'});
    expect(c.read(libraryModeProvider), LibraryMode.sectioned);
  });

  test('cycle wraps sectioned -> publisher -> flat -> sectioned', () async {
    final c = await makeContainer({});
    final n = c.read(libraryModeProvider.notifier);
    n.cycle();
    expect(c.read(libraryModeProvider), LibraryMode.publisher);
    n.cycle();
    expect(c.read(libraryModeProvider), LibraryMode.flat);
    n.cycle();
    expect(c.read(libraryModeProvider), LibraryMode.sectioned);
  });

  test('persists the selection', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(
      overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
    );
    c.read(libraryModeProvider.notifier).select(LibraryMode.flat);
    expect(prefs.getString('library_mode'), 'flat');
  });
}
