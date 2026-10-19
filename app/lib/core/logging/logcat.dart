import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:logging/logging.dart';

/// Тег приложения в logcat: `adb logcat -s milionchik`.
const String logcatTag = 'milionchik';

/// Предел одной записи logcat с запасом (у Android ~4 КБ на запись,
/// длиннее — обрезается).
const int logcatMaxEntryBytes = 4000;

// Приоритеты из android/log.h.
const int _androidLogDebug = 3;
const int _androidLogInfo = 4;
const int _androidLogWarn = 5;
const int _androidLogError = 6;

typedef _LogWriteNative = Int32 Function(
  Int32 priority,
  Pointer<Utf8> tag,
  Pointer<Utf8> text,
);
typedef _LogWriteDart = int Function(
  int priority,
  Pointer<Utf8> tag,
  Pointer<Utf8> text,
);

/// Запись в logcat напрямую через `__android_log_write` (FFI): синхронно,
/// в любом изоляте, до инициализации Flutter и в момент падения.
class Logcat {
  Logcat._(this._write, this._tag);

  /// `null` не на Android (тесты на компьютере).
  static Logcat? open({String tag = logcatTag}) {
    if (!Platform.isAndroid) return null;
    final write = DynamicLibrary.open('liblog.so')
        .lookupFunction<_LogWriteNative, _LogWriteDart>('__android_log_write');
    // Тег живёт всё время процесса — память не освобождаем.
    return Logcat._(write, tag.toNativeUtf8());
  }

  final _LogWriteDart _write;
  final Pointer<Utf8> _tag;

  /// Пишет запись построчно (стек — отдельными строками), длинные строки
  /// режутся по [logcatMaxEntryBytes].
  void write(Level level, String text) {
    final priority = level >= Level.SEVERE
        ? _androidLogError
        : level >= Level.WARNING
        ? _androidLogWarn
        : level >= Level.INFO
        ? _androidLogInfo
        : _androidLogDebug;
    for (final chunk in splitForLogcat(text)) {
      final native = chunk.toNativeUtf8();
      try {
        _write(priority, _tag, native);
      } finally {
        malloc.free(native);
      }
    }
  }
}

/// Делит текст на строки, а строки длиннее [maxBytes] байт UTF-8 — на куски
/// по границе символа.
List<String> splitForLogcat(String text, {int maxBytes = logcatMaxEntryBytes}) {
  final result = <String>[];
  for (final line in text.split('\n')) {
    if (utf8.encode(line).length <= maxBytes) {
      result.add(line);
      continue;
    }
    var used = 0;
    var chunk = StringBuffer();
    for (final rune in line.runes) {
      final size = utf8.encode(String.fromCharCode(rune)).length;
      if (used + size > maxBytes) {
        result.add(chunk.toString());
        chunk = StringBuffer();
        used = 0;
      }
      chunk.writeCharCode(rune);
      used += size;
    }
    if (chunk.isNotEmpty) result.add(chunk.toString());
  }
  return result;
}
