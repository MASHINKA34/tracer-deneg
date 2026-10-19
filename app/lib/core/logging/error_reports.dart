import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:shared/logging.dart';

final _log = Logger('errors');

/// Очередь отчётов об ошибках для `/client-errors` (00-spec §8, §13).
///
/// Пока только пишется в `logs/pending_reports.jsonl` — по строке JSON
/// на ошибку; отправка на сервер появится на этапе 10. Без личных данных:
/// тип и текст ошибки, стек, версия приложения и устройство.
class ErrorReportQueue {
  ErrorReportQueue({this.maxFileBytes = 512 * 1024});

  /// Больше этого размера новые отчёты не пишутся (только в лог).
  final int maxFileBytes;

  /// Версия приложения и устройство — дописываются в каждый отчёт.
  Map<String, Object?> context = const {};

  File? _file;
  final List<Map<String, Object?>> _pending = [];

  File? get file => _file;

  /// Подключает файл очереди; отчёты, накопленные до этого, дописываются.
  void attach(File file) {
    _file = file;
    final pending = List.of(_pending);
    _pending.clear();
    for (final report in pending) {
      _write(report);
    }
    _log.fine('error report queue ${file.path} pending=${pending.length}');
  }

  /// Ставит отчёт в очередь. [kind]: `crash` (необработанная ошибка),
  /// `error` (ошибка фреймворка), позже `user_report`.
  void add(String kind, Object error, StackTrace? stack) {
    final report = <String, Object?>{
      'kind': kind,
      'occurredAt': DateTime.now().toUtc().toIso8601String(),
      'message': describeError(error),
      'stack': stack?.toString(),
      ...context,
    };
    if (_file == null) {
      _pending.add(report);
    } else {
      _write(report);
    }
  }

  void _write(Map<String, Object?> report) {
    final file = _file!;
    try {
      final size = file.existsSync() ? file.lengthSync() : 0;
      if (size >= maxFileBytes) {
        _log.warning(
          'error report queue full (${file.path} size=$size ≥ $maxFileBytes), '
          'report kind=${report['kind']} not queued',
        );
        return;
      }
      file.writeAsStringSync(
        '${jsonEncode(report)}\n',
        mode: FileMode.append,
        flush: true,
      );
      _log.info('error report queued kind=${report['kind']} file=${file.path}');
    } catch (e, st) {
      _log.warning(
        'error report write failed ${file.path}: ${describeError(e)}',
        e,
        st,
      );
    }
  }
}
