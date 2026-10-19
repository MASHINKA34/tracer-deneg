import 'package:flutter/widgets.dart';
import 'package:logging/logging.dart';

final _log = Logger('nav');

/// Пишет в лог каждый переход между экранами (observer для go_router).
class NavigationLogger extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _log.info('push ${_name(route)} (from ${_name(previousRoute)})');

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _log.info('pop ${_name(route)} (back to ${_name(previousRoute)})');

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _log.info('replace ${_name(oldRoute)} → ${_name(newRoute)}');

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _log.info('remove ${_name(route)}');

  static String _name(Route<dynamic>? route) {
    if (route == null) return '-';
    return route.settings.name ?? route.runtimeType.toString();
  }
}
