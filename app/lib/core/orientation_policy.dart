import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:logging/logging.dart';
import 'package:shared/logging.dart';

final _log = Logger('orientation');

/// С какой наименьшей стороны (dp) экран считается большим (00-spec §3).
const double largeScreenMinShortestSide = 600;

/// Телефон (наименьшая сторона < 600 dp) — только портрет; планшет или
/// раскрытая раскладушка — любая ориентация (пустой список = без ограничений).
List<DeviceOrientation> preferredOrientationsFor(double shortestSide) =>
    shortestSide < largeScreenMinShortestSide
    ? const [DeviceOrientation.portraitUp]
    : const [];

/// Задаёт ориентацию при старте и пересчитывает её при смене размера окна
/// (раскладушку раскрыли/сложили). В лог — только смены категории.
class OrientationPolicy with WidgetsBindingObserver {
  bool? _phone;

  void start() {
    WidgetsBinding.instance.addObserver(this);
    _apply('start');
  }

  @override
  void didChangeMetrics() => _apply('window metrics changed');

  void _apply(String reason) {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) {
      _log.fine('no views yet ($reason)');
      return;
    }
    final view = views.first;
    final size = view.physicalSize / view.devicePixelRatio;
    if (size.isEmpty) {
      _log.fine('window size unknown yet ($reason)');
      return;
    }
    final shortest = size.shortestSide;
    final phone = shortest < largeScreenMinShortestSide;
    if (phone == _phone) return;
    _phone = phone;
    _log.info(
      '${phone ? 'portrait only' : 'any orientation'}: '
      'shortestSide=${shortest.round()}dp size=${size.width.round()}x'
      '${size.height.round()}dp ($reason)',
    );
    unawaited(
      SystemChrome.setPreferredOrientations(preferredOrientationsFor(shortest))
          .catchError((Object e, StackTrace st) {
            _log.warning(
              'setPreferredOrientations failed: ${describeError(e)}',
              e,
              st,
            );
          }),
    );
  }
}
