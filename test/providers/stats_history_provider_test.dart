import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/providers/stats_provider.dart';

void main() {
  // Regression: build() used to call _loadPage synchronously, which writes
  // state before build() returns -> "uninitialized provider" crash on first read.
  test('reading statsHistoryProvider does not throw during build', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(() => container.read(statsHistoryProvider), returnsNormally);
    expect(container.read(statsHistoryProvider).sessions, isEmpty);
  });
}
