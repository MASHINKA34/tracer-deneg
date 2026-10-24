import 'dart:async';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:shared/logging.dart';
import 'package:shared/logging_io.dart';

import 'logcat.dart';
import 'ring_file_sink.dart';

/// Уровень из `--dart-define=LOG_LEVEL=debug` (по умолчанию info).
const String logLevelDefine = String.fromEnvironment('LOG_LEVEL');

/// Сколько строк держим в памяти, пока файл лога ещё не открыт.
const int _maxPendingLines = 500;

/// Логирование приложения (00-spec §13): `package:logging`, формат из
/// `shared`, вывод в logcat (тег `milionchik`) и в кольцевой файл
/// `logs/app.log` (2 × 1 МБ).
///
/// Порядок: [AppLogging.start] — в первой строке `main` (logcat сразу),
/// [attachFile] — когда известен каталог приложения; строки, записанные
/// до этого, попадают в файл из буфера.
class AppLogging {
  AppLogging._({
    required this.level,
    required this.levelName,
    required this._logcat,
    required this._extraSink,
  });

  /// Включает логирование: уровень из [levelValue] (`LOG_LEVEL`), logcat
  /// на Android, подписка на все логгеры. Неизвестный уровень → info + warn.
  factory AppLogging.start({
    String levelValue = logLevelDefine,
    Logcat? logcat,
    bool openLogcat = true,
    void Function(String line)? extraSink,
  }) {
    registerIoErrorDetails();
    final parsed = parseLogLevel(levelValue);
    final level = parsed ?? Level.INFO;
    final logging = AppLogging._(
      level: level,
      levelName: logLevelName(level),
      logcat: logcat ?? (openLogcat ? Logcat.open() : null),
      extraSink: extraSink,
    );
    Logger.root.level = level;
    logging._subscription = Logger.root.onRecord.listen(logging._onRecord);
    if (parsed == null && levelValue.isNotEmpty) {
      Logger('logging').warning(
        'unknown LOG_LEVEL "$levelValue" → info '
        '(allowed: ${logLevelsByName.keys.join('|')})',
      );
    }
    return logging;
  }

  final Level level;
  final String levelName;
  final Logcat? _logcat;
  final void Function(String line)? _extraSink;
  StreamSubscription<LogRecord>? _subscription;
  RingFileSink? _file;
  final List<String> _pending = [];
  int _droppedPending = 0;

  /// Текущий файл лога или `null`, пока он не подключён.
  File? get logFile => _file?.currentFile;

  File? get previousLogFile => _file?.previousFile;

  /// Открывает кольцевой файл в [logsDir] и дописывает в него строки,
  /// накопленные с начала запуска.
  File attachFile(Directory logsDir, {int maxBytes = 1024 * 1024}) {
    final sink = RingFileSink.open(
      logsDir,
      maxBytes: maxBytes,
      onError: (message, error, stack) {
        // В файл писать уже нельзя — только logcat.
        _logcat?.write(
          Level.SEVERE,
          '[logging] $message: ${describeError(error)}\n$stack',
        );
        _extraSink?.call('[logging] $message: ${describeError(error)}');
      },
    );
    if (_droppedPending > 0) {
      sink.writeLine(
        '… $_droppedPending earlier lines were not written to file '
        '(buffer limit $_maxPendingLines)',
      );
    }
    for (final line in _pending) {
      sink.writeLine(line);
    }
    _pending.clear();
    _file = sink;
    return sink.currentFile;
  }

  void _onRecord(LogRecord record) {
    final text = formatLogRecord(record);
    _logcat?.write(record.level, text);
    _extraSink?.call(text);
    final file = _file;
    if (file != null) {
      file.writeLine(text);
    } else if (_pending.length < _maxPendingLines) {
      _pending.add(text);
    } else {
      _droppedPending++;
    }
  }

  /// Отписка и закрытие файла (тесты; приложение живёт до конца процесса).
  Future<void> dispose() async {
    await _subscription?.cancel();
    _file?.close();
  }
}
