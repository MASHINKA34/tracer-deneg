import '../client_errors/client_error_fields.dart';
import '../client_errors/client_error_store.dart';

const int errorsTableMessageChars = 80;
const int errorsTableAppChars = 20;
const int errorsTableDeviceChars = 24;

List<String> formatErrorsTable(
  ClientErrorPage page, {
  required DateTime since,
  required String sinceText,
}) {
  final header =
      'client errors since ${formatTableTime(since)} '
      '${formatTableOffset(since)} ($sinceText)';
  if (page.rows.isEmpty) return ['$header: none'];

  final columns = [
    'received',
    'id',
    'kind',
    'app',
    'sdk',
    'device',
    'user',
    'stack',
    'logs',
    'message',
  ];
  final cells = [
    for (final row in page.rows)
      [
        formatTableTime(row.receivedAt),
        row.id,
        terminalSafe(row.kind, maxChars: 12),
        terminalSafe(row.appVersion, maxChars: errorsTableAppChars),
        row.androidSdk?.toString() ?? '-',
        row.deviceModel == null
            ? '-'
            : terminalSafe(row.deviceModel!, maxChars: errorsTableDeviceChars),
        row.userId ?? '-',
        formatSize(row.stackBytes),
        formatSize(row.logsBytes),
        terminalSafe(row.message, maxChars: errorsTableMessageChars),
      ],
  ];
  final widths = [
    for (var i = 0; i < columns.length; i++)
      [
        columns[i].length,
        for (final line in cells) line[i].length,
      ].reduce((a, b) => a > b ? a : b),
  ];
  String render(List<String> values) => [
    for (var i = 0; i < values.length; i++)
      i == values.length - 1 ? values[i] : values[i].padRight(widths[i]),
  ].join('  ').trimRight();

  final shown = page.rows.length;
  return [
    '$header: ${page.total} found, showing $shown, newest first',
    render(columns),
    render([for (final width in widths) '-' * width]),
    for (final line in cells) render(line),
    if (page.total > shown)
      '… ${page.total - shown} more not shown, raise --limit to see them',
  ];
}

String terminalSafe(String text, {required int maxChars}) {
  final single = replaceUnsafeChars(
    text,
    replacement: ' ',
  ).replaceAll(RegExp(r'\s+'), ' ').trim();
  final runes = single.runes.toList();
  if (runes.length <= maxChars) return single;
  return '${String.fromCharCodes(runes.take(maxChars - 1))}…';
}

String formatSize(int? bytes) {
  if (bytes == null) return '-';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String formatTableTime(DateTime time) {
  final t = time.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year.toString().padLeft(4, '0')}-${two(t.month)}-${two(t.day)} '
      '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
}

String formatTableOffset(DateTime time) {
  final offset = time.toLocal().timeZoneOffset;
  final sign = offset.isNegative ? '-' : '+';
  final minutes = offset.inMinutes.abs();
  return '$sign${(minutes ~/ 60).toString().padLeft(2, '0')}:'
      '${(minutes % 60).toString().padLeft(2, '0')}';
}
