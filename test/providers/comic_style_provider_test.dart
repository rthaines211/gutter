import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:comic_reader_app/config/comic_style.dart';
import 'package:comic_reader_app/providers/comic_style_provider.dart';
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

  test('defaults to fullPop', () async {
    final c = await makeContainer({});
    expect(c.read(comicStyleProvider), ComicStyle.fullPop);
  });

  test('restores a stored style', () async {
    final c = await makeContainer({'comic_style': 'off'});
    expect(c.read(comicStyleProvider), ComicStyle.off);
  });

  test('rejects an unrecognized stored value', () async {
    final c = await makeContainer({'comic_style': 'nonsense'});
    expect(c.read(comicStyleProvider), ComicStyle.fullPop);
  });

  test('select updates state and persists', () async {
    final c = await makeContainer({});
    c.read(comicStyleProvider.notifier).select(ComicStyle.inkHalftone);
    expect(c.read(comicStyleProvider), ComicStyle.inkHalftone);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('comic_style'), 'inkHalftone');
  });
}
