import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';

import '../features/month/month_controller.dart';
import 'router.dart';

final _log = Logger('nav');

const int maxDeepLinkPlaceLength = 80;

enum DeepLinkTarget { add, month }

final class DeepLink {
  const DeepLink._(this.uri, this.target);

  static DeepLink? of(Uri uri) {
    if (!uri.hasScheme) return null;
    return DeepLink._(uri, _targetOf(uri));
  }

  final Uri uri;
  final DeepLinkTarget? target;

  static DeepLinkTarget? _targetOf(Uri uri) {
    if (uri.scheme != AppRoutes.deepLinkScheme || !uri.hasAuthority) {
      return null;
    }
    if (uri.path.isNotEmpty && uri.path != '/') return null;
    return switch (uri.host) {
      AppRoutes.addDeepLinkHost => DeepLinkTarget.add,
      AppRoutes.monthDeepLinkHost => DeepLinkTarget.month,
      _ => null,
    };
  }

  String get place {
    final text = Uri(
      scheme: uri.scheme,
      host: uri.hasAuthority ? uri.host : null,
      path: uri.path == '/' ? '' : uri.path,
    ).toString();
    if (text.length <= maxDeepLinkPlaceLength) return text;
    return '${text.substring(0, maxDeepLinkPlaceLength)}…'
        '(${text.length} chars)';
  }

  String get _extras => uri.hasQuery || uri.hasFragment ? ' query=ignored' : '';
}

final class DeepLinkRouting {
  DeepLinkRouting({required this.rootKey, required this.router});

  final GlobalKey<NavigatorState> rootKey;
  final GoRouter Function() router;

  DeepLink? _waiting;
  int _ticket = 0;

  String? redirect(Uri uri, {required String? signIn}) {
    final link = DeepLink.of(uri);
    if (link != null) return _received(link, signIn);
    if (signIn != null) return signIn;
    final waiting = _waiting;
    if (waiting == null || AppRoutes.isAuthStack(uri.path)) return null;
    _waiting = null;
    final target = waiting.target!;
    _log.info(
      'deep link ${waiting.place} after sign-in → ${_describe(target)}',
    );
    return _open(target);
  }

  String _received(DeepLink link, String? signIn) {
    final current = router().routerDelegate.currentConfiguration;
    final start = current.isEmpty
        ? 'start=cold'
        : 'start=warm from=${current.uri.path}';
    final what = 'deep link ${link.place} $start${link._extras}';
    final target = link.target;
    if (signIn != null) {
      _waiting = target == null ? null : link;
      if (target == null) {
        _log.warning(
          '$what: unknown link, ${_known()} → $signIn, nothing to open after '
          'sign-in',
        );
      } else {
        _log.info('$what → $signIn first, ${_describe(target)} after sign-in');
      }
      return signIn;
    }
    if (_waiting != null) {
      _log.fine(
        'deep link ${_waiting!.place} waiting for sign-in replaced by '
        '${link.place}',
      );
      _waiting = null;
    }
    if (target == null) {
      _ticket++;
      _log.warning('$what: unknown link, ${_known()} → ${AppRoutes.month}');
      return AppRoutes.month;
    }
    _log.info('$what → ${_describe(target)}');
    return _open(target);
  }

  String _open(DeepLinkTarget target) {
    final ticket = ++_ticket;
    SchedulerBinding.instance
      ..addPostFrameCallback((_) => _afterFrame(target, ticket))
      ..ensureVisualUpdate();
    return AppRoutes.month;
  }

  void _afterFrame(DeepLinkTarget target, int ticket) {
    if (ticket != _ticket) {
      _log.fine(
        'deep link ${target.name}: replaced by a newer link before '
        '${AppRoutes.month} was shown, skipping',
      );
      return;
    }
    final navigator = rootKey.currentState;
    if (navigator == null) {
      _log.warning(
        'deep link ${target.name}: no root navigator after the frame, '
        'staying where the router is',
      );
      return;
    }
    _closePopups(target, navigator);
    switch (target) {
      case DeepLinkTarget.add:
        _log.fine(
          'deep link add: ${AppRoutes.month} is shown, pushing '
          '${AppRoutes.newExpense}',
        );
        unawaited(router().push<void>(AppRoutes.newExpense));
      case DeepLinkTarget.month:
        _log.fine(
          'deep link month: ${AppRoutes.month} is shown, switching to the '
          'current month',
        );
        ProviderScope.containerOf(
          navigator.context,
          listen: false,
        ).read(monthControllerProvider.notifier).openCurrent(by: 'link');
    }
  }

  void _closePopups(DeepLinkTarget target, NavigatorState navigator) {
    final closed = <String>[];
    navigator.popUntil((route) {
      if (route.settings is Page<Object?>) return true;
      closed.add(route.settings.name ?? route.runtimeType.toString());
      return false;
    });
    if (closed.isEmpty) return;
    _log.fine(
      'deep link ${target.name}: closed ${closed.length} sheet/dialog over '
      'the app: ${closed.join(', ')}',
    );
  }

  static String _known() =>
      'known: ${AppRoutes.deepLinkScheme}://${AppRoutes.addDeepLinkHost}, '
      '${AppRoutes.deepLinkScheme}://${AppRoutes.monthDeepLinkHost}';

  static String _describe(DeepLinkTarget target) => switch (target) {
    DeepLinkTarget.add => '${AppRoutes.newExpense} over ${AppRoutes.month}',
    DeepLinkTarget.month => '${AppRoutes.month} on the current month',
  };
}
