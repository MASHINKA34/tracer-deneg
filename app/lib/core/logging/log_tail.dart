import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

final _log = Logger('errors');

final RegExp _recordStart = RegExp(
  r'^\d{4}-\d{2}-\d{2}T\S+ (DEBUG|INFO|WARN|ERROR) +\[',
);

final class LogTail {
  const LogTail({
    required this.text,
    required this.bytes,
    required this.sourceBytes,
    required this.files,
    required this.debugLinesSkipped,
    required this.truncated,
  });

  static const empty = LogTail(
    text: '',
    bytes: 0,
    sourceBytes: 0,
    files: 0,
    debugLinesSkipped: 0,
    truncated: false,
  );

  final String text;
  final int bytes;
  final int sourceBytes;
  final int files;
  final int debugLinesSkipped;
  final bool truncated;
}

LogTail readLogTail(
  List<File> files, {
  int maxBytes = maxClientErrorLogsBytes,
}) {
  final sw = Stopwatch()..start();
  final buffer = StringBuffer();
  var sourceBytes = 0;
  var read = 0;
  for (final file in files) {
    if (!file.existsSync()) {
      _log.fine('log tail: ${file.path} absent → skipped');
      continue;
    }
    final bytes = file.readAsBytesSync();
    sourceBytes += bytes.length;
    read++;
    final text = utf8.decode(bytes, allowMalformed: true);
    buffer.write(text);
    if (text.isNotEmpty && !text.endsWith('\n')) buffer.write('\n');
  }
  final tail = logTailOf(buffer.toString(), maxBytes: maxBytes);
  final result = LogTail(
    text: tail.text,
    bytes: tail.bytes,
    sourceBytes: sourceBytes,
    files: read,
    debugLinesSkipped: tail.debugLinesSkipped,
    truncated: tail.truncated,
  );
  _log.fine(
    'log tail read files=$read sourceBytes=$sourceBytes bytes=${result.bytes} '
    'limit=$maxBytes debugSkipped=${result.debugLinesSkipped} '
    'truncated=${result.truncated} in ${sw.elapsedMilliseconds}ms',
  );
  return result;
}

({String text, int bytes, int debugLinesSkipped, bool truncated}) logTailOf(
  String source, {
  int maxBytes = maxClientErrorLogsBytes,
}) {
  final kept = <String>[];
  var skipped = 0;
  var inDebug = false;
  for (final line in const LineSplitter().convert(source)) {
    final start = _recordStart.firstMatch(line);
    if (start != null) inDebug = start.group(1) == 'DEBUG';
    if (inDebug) {
      skipped++;
    } else {
      kept.add(line);
    }
  }

  var used = 0;
  var first = kept.length;
  while (first > 0) {
    final size = _utf8Length(kept[first - 1]) + 1;
    if (used + size > maxBytes) break;
    used += size;
    first--;
  }
  final truncated = first > 0;
  final lines = kept.sublist(first);
  if (lines.isEmpty && kept.isNotEmpty) {
    final last = _tailOfLine(kept.last, maxBytes);
    return (
      text: last,
      bytes: _utf8Length(last),
      debugLinesSkipped: skipped,
      truncated: true,
    );
  }
  final text = lines.isEmpty ? '' : '${lines.join('\n')}\n';
  return (
    text: text,
    bytes: used,
    debugLinesSkipped: skipped,
    truncated: truncated,
  );
}

String _tailOfLine(String line, int maxBytes) {
  final runes = line.runes.toList();
  var used = 0;
  var start = runes.length;
  while (start > 0) {
    final size = _runeBytes(runes[start - 1]);
    if (used + size > maxBytes) break;
    used += size;
    start--;
  }
  return String.fromCharCodes(runes, start);
}

int _utf8Length(String text) {
  var bytes = 0;
  for (final rune in text.runes) {
    bytes += _runeBytes(rune);
  }
  return bytes;
}

int _runeBytes(int rune) => rune < 0x80
    ? 1
    : rune < 0x800
    ? 2
    : rune < 0x10000
    ? 3
    : 4;
