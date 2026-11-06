import 'package:comic_reader_app/providers/providers.dart';
import 'package:comic_reader_app/providers/smart_filter_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Komga/Kavita sources have no smart filters and fetch nothing', () async {
    // apiClientProvider is left unoverridden: touching it would throw.
    final c = ProviderContainer(overrides: [
      isCustomSourceProvider.overrideWithValue(false),
    ]);
    addTearDown(c.dispose);
    final sub = c.listen(smartFilterListProvider, (_, _) {});
    addTearDown(sub.close);
    expect(await c.read(smartFilterListProvider.future), isEmpty);
  });
}
