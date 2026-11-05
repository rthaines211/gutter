import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/services/app_logger.dart';
import 'package:comic_reader_app/services/breadcrumb_route_observer.dart';

PageRoute<dynamic> _route(String name) =>
    MaterialPageRoute(builder: (_) => const SizedBox(), settings: RouteSettings(name: name));

void main() {
  setUp(() {
    AppLogger.resetForTest();
  });

  test('didPush records the new route', () {
    final logger = AppLogger.forTest();
    final pushed = <String>[];
    final observer = BreadcrumbRouteObserver(
      onRoute: pushed.add,
      logger: logger,
    );

    observer.didPush(_route('/reader'), _route('/library'));

    expect(pushed, ['/reader']);
    final entries = logger.snapshot(category: LogCategory.lifecycle);
    expect(entries.length, 1);
    expect(entries.single.message, contains('push'));
    expect(entries.single.context['route'], '/reader');
  });

  test('didPop records the previous route', () {
    final logger = AppLogger.forTest();
    final pushed = <String>[];
    final observer = BreadcrumbRouteObserver(
      onRoute: pushed.add,
      logger: logger,
    );

    observer.didPop(_route('/reader'), _route('/library'));

    expect(pushed, ['/library']);
    expect(
      logger.snapshot(category: LogCategory.lifecycle).single.message,
      contains('pop'),
    );
  });

  test('handles null route names by emitting "unknown"', () {
    final logger = AppLogger.forTest();
    final pushed = <String>[];
    final observer = BreadcrumbRouteObserver(
      onRoute: pushed.add,
      logger: logger,
    );

    observer.didPush(
      MaterialPageRoute(builder: (_) => const SizedBox()),
      null,
    );

    expect(pushed, ['unknown']);
  });
}
