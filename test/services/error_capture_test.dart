import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/services/app_logger.dart';
import 'package:comic_reader_app/services/error_capture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => AppLogger.resetForTest());

  test('FlutterError hook forwards to AppLogger and original handler', () {
    final logger = AppLogger.forTest();
    var originalCalled = false;
    final restore = installErrorCapture(
      logger: logger,
      originalFlutterError: (_) => originalCalled = true,
    );

    FlutterError.reportError(FlutterErrorDetails(
      exception: StateError('boom'),
      library: 'test',
    ));

    final entries = logger.snapshot(category: LogCategory.error);
    expect(entries.length, 1);
    expect(entries.single.message, contains('boom'));
    expect(originalCalled, isTrue);

    restore();
  });
}
