import 'package:flutter/material.dart';
import 'app_logger.dart';

typedef RouteCallback = void Function(String route);

class BreadcrumbRouteObserver extends RouteObserver<PageRoute<dynamic>> {
  BreadcrumbRouteObserver({required this.onRoute, AppLogger? logger})
      : _logger = logger;

  final RouteCallback onRoute;
  final AppLogger? _logger;
  AppLogger get _log => _logger ?? AppLogger.instance;

  String _name(Route<dynamic>? route) =>
      route?.settings.name ?? 'unknown';

  void _record(String op, Route<dynamic>? current, Route<dynamic>? previous) {
    final name = _name(current);
    onRoute(name);
    _log.lifecycle(
      level: LogLevel.info,
      message: 'route $op: $name',
      context: {
        'route': name,
        'previous': _name(previous),
        'op': op,
      },
    );
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _record('push', route, previousRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    _record('pop', previousRoute, route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    _record('replace', newRoute, oldRoute);
  }
}
