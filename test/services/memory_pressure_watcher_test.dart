import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/services/app_logger.dart';
import 'package:comic_reader_app/services/memory_pressure_watcher.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    AppLogger.resetForTest();
  });

  test('didHaveMemoryPressure clears injected cache and logs', () {
    final logger = AppLogger.forTest();
    var cleared = false;
    final watcher = MemoryPressureWatcher(
      logger: logger,
      cacheStats: () => (count: 87, bytes: 250000000),
      onClear: () => cleared = true,
    );

    watcher.didHaveMemoryPressure();

    expect(cleared, isTrue);
    final entries = logger.snapshot(category: LogCategory.memory);
    expect(entries.length, 1);
    expect(entries.single.context['beforeCount'], 87);
    expect(entries.single.context['beforeBytes'], 250000000);
    expect(entries.single.level, LogLevel.warn);
  });
}
