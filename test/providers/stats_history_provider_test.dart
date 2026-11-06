import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/providers/cache_providers.dart';
import 'package:comic_reader_app/providers/mirror_provider.dart';
import 'package:comic_reader_app/providers/providers.dart';
import 'package:comic_reader_app/providers/stats_provider.dart';
import 'package:comic_reader_app/services/api_client.dart';

void main() {
  // Regression: build() used to call _loadPage synchronously, which writes
  // state before build() returns -> "uninitialized provider" crash on first read.
  test('reading statsHistoryProvider does not throw during build', () {
    // build() watches the source's client and session store (history
    // follows source switches); stub them so no platform plugins load.
    final container = ProviderContainer(overrides: [
      apiClientProvider.overrideWithValue(ApiClient(baseUrl: 'http://x', deviceId: 'd')),
      localSessionStoreProvider.overrideWithValue(null),
      isCustomSourceProvider.overrideWithValue(true),
      mirrorLibraryProvider.overrideWith((_) => Stream.value(const [])),
    ]);
    addTearDown(container.dispose);

    expect(() => container.read(statsHistoryProvider), returnsNormally);
    expect(container.read(statsHistoryProvider).sessions, isEmpty);
  });
}
