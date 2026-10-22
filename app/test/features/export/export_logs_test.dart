import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:logging/logging.dart';
import 'package:share_plus/share_plus.dart';

import 'export_fixture.dart';

bool _mentions(LogRecord r, String text) =>
    r.message.contains(text) ||
    '${r.error}'.contains(text) ||
    '${r.stackTrace}'.contains(text);

const List<String> _private = [
  'Хлеб',
  'Простоквашино',
  'Метро',
  'Ёлка',
  'Сентябрь',
  'Личный',
  'lichnyj',
  '149,90',
  '12500',
  '13 354',
  '13354',
];

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testWidgets('успешный экспорт: info [export] — период, число строк, '
      'размер файла и результат «Поделиться»; комментариев, названий и '
      'сумм на info нет', (tester) async {
    final h = await ExportHarness.open(tester);
    h.records.clear();

    await h.share();

    final info = [for (final r in h.exportLogs(Level.INFO)) r.message];
    expect(info, [
      matches(
        r'^export started budgetId=\S+ period=2026-10-01\.\.2026-10-31 '
        r'kind=month rows=4$',
      ),
      matches(
        r'^export file ready budgetId=\S+ period=2026-10-01\.\.2026-10-31 '
        r'kind=month rows=4 size=389B in \d+ms, opening share sheet$',
      ),
      matches(
        r'^export share result=success '
        r'target=com\.android\.documentsui/\.picker\.SaveActivity rows=4 '
        r'size=389B after \d+ms$',
      ),
    ]);
    for (final text in _private) {
      expect(
        h.records.where((r) => r.level >= Level.INFO && _mentions(r, text)),
        isEmpty,
        reason: text,
      );
    }
    expect(h.records.where((r) => r.level >= Level.WARNING), isEmpty);
  });

  testWidgets('«Поделиться» закрыли без выбора — info result=dismissed '
      'target=-', (tester) async {
    final h = await ExportHarness.open(tester);
    h.sharer.result = const ShareResult('', ShareResultStatus.dismissed);

    await h.share();

    expect(
      h.exportLogs(Level.INFO).last.message,
      matches(r'^export share result=dismissed target=- rows=4 size=389B '),
    );
  });

  testWidgets('файл не записался — error [export] с путём и причиной, '
      'снекбар, «Поделиться» не открывается', (tester) async {
    final blockerDir = Directory.systemTemp.createTempSync('milionchik_blk_');
    addTearDown(() => blockerDir.deleteSync(recursive: true));
    final blocker = File('${blockerDir.path}${Platform.pathSeparator}cache')
      ..writeAsStringSync('not a folder');
    final target = Directory('${blocker.path}${Platform.pathSeparator}export');
    final h = await ExportHarness.open(tester, directory: () async => target);
    h.records.clear();

    await tester.tap(h.shareButton);
    await h.settle(
      until: () => find
          .text('Не получилось сохранить файл. Попробуй ещё раз')
          .evaluate()
          .isNotEmpty,
    );

    expect(
      find.text('Не получилось сохранить файл. Попробуй ещё раз'),
      findsOneWidget,
    );
    expect(h.sharer.paths, isEmpty);
    final errors = h.exportLogs(Level.SEVERE).toList();
    expect(errors, hasLength(1));
    expect(
      errors.single.message,
      startsWith(
        'export file write failed path=${target.path}'
        '${Platform.pathSeparator}milionchik_lichnyj_2026-10.csv size=389B '
        'after ',
      ),
    );
    expect(errors.single.message, contains('OS Error'));
    expect(errors.single.error, isA<FileSystemException>());
    expect(errors.single.stackTrace, isNotNull);
    expect(
      h.exportLogs(Level.WARNING).single.message,
      matches(
        r'^export aborted budgetId=\S+ period=2026-10-01\.\.2026-10-31 '
        r'kind=month after \d+ms: file not written \(\w+\), snackbar shown$',
      ),
    );
    for (final text in ['Хлеб', 'Метро', 'Ёлка', '149,90', '12500']) {
      expect(h.records.where((r) => _mentions(r, text)), isEmpty);
    }
  });

  testWidgets('«Поделиться» упало — error [export] с путём файла и '
      'PlatformException, снекбар', (tester) async {
    final h = await ExportHarness.open(tester);
    h.sharer.error = PlatformException(
      code: 'Share callback error',
      message: 'prior share-sheet did not call back, did you await it?',
    );
    h.records.clear();

    await h.share();

    expect(
      find.text('Не получилось открыть «Поделиться». Попробуй ещё раз'),
      findsOneWidget,
    );
    final error = h.exportLogs(Level.SEVERE).single;
    expect(
      error.message,
      matches(
        r'^export share failed path=.*milionchik_lichnyj_2026-10\.csv after '
        r'\d+ms, snackbar shown: PlatformException.*Share callback error',
      ),
    );
    expect(error.error, isA<PlatformException>());
  });
}
