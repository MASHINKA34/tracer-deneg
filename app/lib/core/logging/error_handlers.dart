import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:shared/logging.dart';

import 'error_reports.dart';

final _log = Logger('errors');

/// Глобальные перехватчики ошибок главного изолята (00-spec §13): ошибки
/// фреймворка и необработанные (в т.ч. асинхронные) ошибки. Каждая — в лог
/// с полным стеком и в очередь отчётов [reports].
///
/// `Isolate.addErrorListener` в главном изоляте не ставим: проверено на
/// эмуляторе — с ним VM отдаёт ошибку слушателю вместо
/// `PlatformDispatcher.onError`, и теряется тип (приходит только строка).
/// Фоновые изоляты (workmanager, виджет) ставят свои перехватчики сами.
void installErrorHandlers(ErrorReportQueue reports) {
  final previousOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    final context = details.context?.toDescription();
    _log.severe(
      'Flutter error${details.library == null ? '' : ' in ${details.library}'}'
      '${context == null ? '' : ' ($context)'}: '
      '${describeError(details.exception)}',
      details.exception,
      details.stack,
    );
    reports.add('error', details.exception, details.stack);
    // В debug ещё и стандартный вывод Flutter в консоль `flutter run`.
    if (kDebugMode) previousOnError?.call(details);
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    _log.severe('uncaught error: ${describeError(error)}', error, stack);
    reports.add('crash', error, stack);
    return true;
  };

  _log.fine('error handlers installed: FlutterError, PlatformDispatcher');
}
