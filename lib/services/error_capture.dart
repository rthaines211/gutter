import 'package:flutter/foundation.dart';

import 'app_logger.dart';

typedef RestoreErrorCapture = void Function();

RestoreErrorCapture installErrorCapture({
  AppLogger? logger,
  FlutterExceptionHandler? originalFlutterError,
}) {
  final log = logger ?? AppLogger.instance;
  final previousFlutterError = originalFlutterError ?? FlutterError.onError;
  final previousPlatformError = PlatformDispatcher.instance.onError;

  FlutterError.onError = (details) {
    log.error(
      level: LogLevel.error,
      message: 'FlutterError: ${details.exceptionAsString()}',
      context: {
        'library': details.library ?? '',
        'stack': details.stack?.toString() ?? '',
      },
    );
    previousFlutterError?.call(details);
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    log.error(
      level: LogLevel.error,
      message: 'PlatformDispatcher: $error',
      context: {'stack': stack.toString()},
    );
    return previousPlatformError?.call(error, stack) ?? false;
  };

  return () {
    FlutterError.onError = previousFlutterError;
    PlatformDispatcher.instance.onError = previousPlatformError;
  };
}
