// test/providers/scheme_provider_test.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:comic_reader_app/config/scheme.dart';
import 'package:comic_reader_app/providers/providers.dart';
import 'package:comic_reader_app/providers/scheme_provider.dart';

Future<ProviderContainer> makeContainer(Map<String, Object> initial) async {
  SharedPreferences.setMockInitialValues(initial);
  final prefs = await SharedPreferences.getInstance();
  return ProviderContainer(
    overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('defaults to Sepia/Paper when nothing is stored', () async {
    final c = await makeContainer({});
    expect(c.read(schemeProvider), SchemeId.sepiaPaper);
    expect(c.read(schemeProvider).scheme, Scheme.sepiaPaper);
  });

  test('restores a stored scheme', () async {
    // Stores oledBlack specifically: a stored value must beat the default,
    // which is the escape hatch for anyone who prefers the dark scheme.
    final c = await makeContainer({'theme_scheme': 'oledBlack'});
    expect(c.read(schemeProvider), SchemeId.oledBlack);
  });

  test('falls back to the default on an unrecognised stored value', () async {
    final c = await makeContainer({'theme_scheme': 'nonsense'});
    expect(c.read(schemeProvider), SchemeId.sepiaPaper);
  });

  test('select updates state and persists', () async {
    final c = await makeContainer({});
    // Selects away from the default, so this cannot pass by accident.
    c.read(schemeProvider.notifier).select(SchemeId.oledBlack);
    expect(c.read(schemeProvider), SchemeId.oledBlack);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('theme_scheme'), 'oledBlack');
  });
}
