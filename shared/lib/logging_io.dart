/// Подробности ошибок `dart:io` для лога (errno и т.п.).
///
/// Только для платформ с `dart:io` (сервер, Android), поэтому не входит
/// в `shared.dart` — веб-сборка его не импортирует.
library;

import 'dart:io';

import 'logging.dart';

/// Подключает [ioErrorDetails] к [describeError].
void registerIoErrorDetails() => registerErrorDetailsExtractor(ioErrorDetails);

/// Код ошибки ОС из исключений `dart:io`: `errno=10061`.
Map<String, Object?>? ioErrorDetails(Object error) => switch (error) {
  SocketException(:final osError) => {'errno': osError?.errorCode},
  FileSystemException(:final osError) => {'errno': osError?.errorCode},
  OSError(:final errorCode) => {'errno': errorCode},
  _ => null,
};
