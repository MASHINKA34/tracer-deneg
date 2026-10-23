import 'dart:convert';

import 'package:cryptography/dart.dart' show DartSha256;
import 'package:shared/shared.dart';

const int maxClientErrorTextBytes = maxClientErrorLogsBytes;
const int maxClientErrorAppVersionBytes = 64;
const int maxClientErrorDeviceModelBytes = 128;
const int maxClientErrorAndroidSdk = 2147483647;

final class PreparedClientError {
  const PreparedClientError({
    required this.kind,
    required this.appVersion,
    required this.androidSdk,
    required this.deviceModel,
    required this.message,
    required this.stack,
    required this.logs,
    required this.truncated,
    required this.nulReplaced,
  });

  final ClientErrorKind kind;
  final String appVersion;
  final int? androidSdk;
  final String? deviceModel;
  final String message;
  final String? stack;
  final String? logs;
  final List<String> truncated;
  final int nulReplaced;

  int get messageBytes => utf8Length(message);
  int? get stackBytes => stack == null ? null : utf8Length(stack!);
  int? get logsBytes => logs == null ? null : utf8Length(logs!);
}

PreparedClientError prepareClientError(ClientErrorReport report) {
  final truncated = <String>[];
  var nulReplaced = 0;

  String fit(
    String field,
    String value,
    int maxBytes,
    String Function(String, int) limit,
  ) {
    final nuls = '\u0000'.allMatches(value).length;
    final clean = nuls == 0 ? value : value.replaceAll('\u0000', '\uFFFD');
    nulReplaced += nuls;
    final limited = limit(clean, maxBytes);
    if (!identical(limited, clean)) truncated.add(field);
    return limited;
  }

  String? fitOpt(
    String field,
    String? value,
    int maxBytes,
    String Function(String, int) limit,
  ) => value == null ? null : fit(field, value, maxBytes, limit);

  return PreparedClientError(
    kind: report.kind,
    appVersion: fit(
      'appVersion',
      report.appVersion,
      maxClientErrorAppVersionBytes,
      limitHead,
    ),
    androidSdk: report.androidSdk,
    deviceModel: fitOpt(
      'deviceModel',
      report.deviceModel,
      maxClientErrorDeviceModelBytes,
      limitHead,
    ),
    message: fit('message', report.message, maxClientErrorTextBytes, limitHead),
    stack: fitOpt('stack', report.stack, maxClientErrorTextBytes, limitHead),
    logs: fitOpt('logs', report.logs, maxClientErrorTextBytes, limitTail),
    truncated: List.unmodifiable(truncated),
    nulReplaced: nulReplaced,
  );
}

int utf8Length(String text) {
  var bytes = 0;
  for (final rune in text.runes) {
    bytes += _runeBytes(rune);
  }
  return bytes;
}

String limitHead(String text, int maxBytes) {
  final total = utf8Length(text);
  if (total <= maxBytes) return text;
  final marker = '…[truncated, total $total bytes]';
  final budget = maxBytes - utf8Length(marker);
  if (budget < 0) return _head(text.runes.toList(), maxBytes);
  return '${_head(text.runes.toList(), budget)}$marker';
}

String limitTail(String text, int maxBytes) {
  final total = utf8Length(text);
  if (total <= maxBytes) return text;
  final marker = '[truncated, total $total bytes]…';
  final budget = maxBytes - utf8Length(marker);
  if (budget < 0) return _tail(text.runes.toList(), maxBytes);
  return '$marker${_tail(text.runes.toList(), budget)}';
}

String textFingerprint(String text) {
  final digest = const DartSha256().hashSync(utf8.encode(text)).bytes;
  return [
    for (final byte in digest.take(6)) byte.toRadixString(16).padLeft(2, '0'),
  ].join();
}

final RegExp _unsafeChars = RegExp(
  r'[\u0000-\u001f\u007f-\u009f\u200e\u200f\u202a-\u202e\u2066-\u2069]',
);

String replaceUnsafeChars(String text, {String replacement = '?'}) =>
    text.replaceAll(_unsafeChars, replacement);

String logSafe(String text, {int maxBytes = 64}) =>
    truncateBody(replaceUnsafeChars(text), maxBytes: maxBytes);

String _head(List<int> runes, int budget) {
  var used = 0;
  var end = 0;
  while (end < runes.length) {
    final size = _runeBytes(runes[end]);
    if (used + size > budget) break;
    used += size;
    end++;
  }
  return String.fromCharCodes(runes, 0, end);
}

String _tail(List<int> runes, int budget) {
  var used = 0;
  var start = runes.length;
  while (start > 0) {
    final size = _runeBytes(runes[start - 1]);
    if (used + size > budget) break;
    used += size;
    start--;
  }
  return String.fromCharCodes(runes, start);
}

int _runeBytes(int rune) => rune < 0x80
    ? 1
    : rune < 0x800
    ? 2
    : rune < 0x10000
    ? 3
    : 4;
