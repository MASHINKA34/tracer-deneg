import 'dart:convert';
import 'dart:io';

/// Сообщает о сбое записи в файл туда, где его увидят (logcat).
typedef SinkErrorReporter = void Function(
  String message,
  Object error,
  StackTrace stack,
);

/// Кольцевой лог: `app.log` до [maxBytes], затем он становится `app.log.1`
/// (старый `.1` удаляется) и начинается новый `app.log`. Всего не больше
/// двух файлов. Пишет синхронно — строка падения успевает попасть в файл.
class RingFileSink {
  RingFileSink._(this.directory, this.maxBytes, this._onError, this._file)
    : _size = _file.lengthSync();

  /// Открывает (создаёт) `app.log` в [directory].
  factory RingFileSink.open(
    Directory directory, {
    int maxBytes = 1024 * 1024,
    String fileName = 'app.log',
    required SinkErrorReporter onError,
  }) {
    directory.createSync(recursive: true);
    final file = File('${directory.path}${Platform.pathSeparator}$fileName');
    return RingFileSink._(
      directory,
      maxBytes,
      onError,
      file.openSync(mode: FileMode.append),
    );
  }

  final Directory directory;
  final int maxBytes;
  final SinkErrorReporter _onError;
  RandomAccessFile _file;
  int _size;
  bool _broken = false;

  /// Текущий файл (`app.log`).
  File get currentFile => File(_file.path);

  /// Предыдущий файл (`app.log.1`).
  File get previousFile => File('${_file.path}.1');

  /// Дописывает строку. Если файл переполнится — сначала ротация.
  /// После сбоя записи файл отключается (о сбое сообщается один раз),
  /// чтобы не зациклиться на ошибках.
  void writeLine(String text) {
    if (_broken) return;
    final bytes = utf8.encode('$text\n');
    try {
      if (_size > 0 && _size + bytes.length > maxBytes) _rotate();
      _file.writeFromSync(bytes);
      _size += bytes.length;
    } catch (e, st) {
      _broken = true;
      _onError(
        'log file write failed ${_file.path} size=$_size, file logging disabled',
        e,
        st,
      );
    }
  }

  void _rotate() {
    final path = _file.path;
    _file.closeSync();
    final previous = File('$path.1');
    if (previous.existsSync()) previous.deleteSync();
    File(path).renameSync(previous.path);
    _file = File(path).openSync(mode: FileMode.append);
    _size = 0;
  }

  void close() {
    try {
      _file.closeSync();
    } catch (e, st) {
      _onError('log file close failed ${_file.path}', e, st);
    }
  }
}
