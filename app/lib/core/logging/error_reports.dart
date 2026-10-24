import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:logging/logging.dart';
import 'package:shared/logging.dart';

import '../../data/db/redact_db_error.dart';

final _log = Logger('errors');

const String providerRethrownMarker = 'rethrown by ProviderException at:';

final class ReportSafeError {
  const ReportSafeError({
    required this.error,
    required this.stack,
    required this.providerDepth,
  });

  final Object error;
  final StackTrace? stack;
  final int providerDepth;

  bool get fromProvider => providerDepth > 0;

  String get origin => fromProvider ? ' (thrown in a provider)' : '';
}

ReportSafeError reportSafeError(Object error, [StackTrace? stack]) {
  var cause = error;
  final stacks = <StackTrace?>[stack];
  while (cause is ProviderException) {
    stacks.add(cause.stackTrace);
    cause = cause.exception;
  }
  final depth = stacks.length - 1;
  if (depth == 0) {
    return ReportSafeError(
      error: redactDbError(cause),
      stack: stack,
      providerDepth: 0,
    );
  }
  final parts = <String>[];
  for (final part in stacks.reversed) {
    final text = part?.toString().trimRight() ?? '';
    if (parts.isNotEmpty) parts.add(providerRethrownMarker);
    parts.add(text.isEmpty ? '<no stack>' : text);
  }
  return ReportSafeError(
    error: redactDbError(cause),
    stack: StackTrace.fromString(parts.join('\n')),
    providerDepth: depth,
  );
}

final class QueuedErrorReport {
  const QueuedErrorReport({required this.line, required this.raw});

  final int line;
  final String raw;
}

/// Очередь отчётов об ошибках для `/client-errors` (00-spec §8, §13).
///
/// Пишется в `logs/pending_reports.jsonl` — по строке JSON на ошибку;
/// `ErrorReportSender` отправляет и удаляет строку после 202. Без личных данных:
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
  /// `error` (ошибка фреймворка); `user_report` уходит сразу, без очереди.
  void add(String kind, Object error, StackTrace? stack) {
    final safe = reportSafeError(error, stack);
    final report = <String, Object?>{
      'kind': kind,
      'occurredAt': DateTime.now().toUtc().toIso8601String(),
      'message': describeError(safe.error),
      'stack': safe.stack?.toString(),
      ...context,
    };
    if (_file == null) {
      _pending.add(report);
    } else {
      _write(report);
    }
  }

  List<QueuedErrorReport> readQueued() {
    final file = _file;
    if (file == null) {
      _log.fine(
        'error report queue not attached → nothing to read '
        '(in memory ${_pending.length})',
      );
      return const [];
    }
    try {
      if (!file.existsSync()) {
        _log.fine('error report queue ${file.path} absent → empty');
        return const [];
      }
      final lines = file.readAsLinesSync();
      final reports = [
        for (var i = 0; i < lines.length; i++)
          if (lines[i].trim().isNotEmpty)
            QueuedErrorReport(line: i + 1, raw: lines[i]),
      ];
      _log.fine(
        'error report queue ${file.path} read reports=${reports.length} '
        'lines=${lines.length}',
      );
      return reports;
    } catch (e, st) {
      _log.warning(
        'error report queue read failed ${file.path}: ${describeError(e)} '
        '→ nothing sent this time',
        e,
        st,
      );
      return const [];
    }
  }

  bool remove(QueuedErrorReport report) {
    final file = _file;
    if (file == null) return false;
    try {
      final lines = file.existsSync() ? file.readAsLinesSync() : <String>[];
      final index = lines.indexOf(report.raw);
      if (index < 0) {
        _log.warning(
          'error report line ${report.line} not found in ${file.path} '
          '(lines=${lines.length}) → nothing removed',
        );
        return false;
      }
      lines.removeAt(index);
      final left = lines.where((l) => l.trim().isNotEmpty).toList();
      if (left.isEmpty) {
        file.deleteSync();
      } else {
        file.writeAsStringSync('${left.join('\n')}\n', flush: true);
      }
      _log.fine(
        'error report line ${report.line} removed from ${file.path} '
        'left=${left.length}',
      );
      return true;
    } catch (e, st) {
      _log.warning(
        'error report remove failed ${file.path} line=${report.line}: '
        '${describeError(e)} → sending stopped to avoid duplicates',
        e,
        st,
      );
      return false;
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
