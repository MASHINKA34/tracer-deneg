import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:logging/logging.dart';

import 'export_fixture.dart';

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testWidgets('повторный экспорт: прежний файл удаляется, в папке экспорта '
      'всегда один файл — тот, что ушёл в «Поделиться»', (tester) async {
    final h = await ExportHarness.open(tester);

    await h.share();
    expect(h.folderFiles, ['milionchik_lichnyj_2026-10.csv']);

    await h.tapText('2026 год');
    await h.share();
    expect(h.folderFiles, ['milionchik_lichnyj_2026.csv']);
    expect(h.sharer.paths.last, endsWith('milionchik_lichnyj_2026.csv'));

    await h.share();
    expect(h.folderFiles, ['milionchik_lichnyj_2026.csv']);
    expect(h.sharer.paths, hasLength(3));

    final deleted = [
      for (final r in h.exportLogs(Level.FINE))
        if (r.message.startsWith('previous export file deleted')) r.message,
    ];
    expect(deleted, [
      'previous export file deleted name=milionchik_lichnyj_2026-10.csv '
          'size=389B',
      'previous export file deleted name=milionchik_lichnyj_2026.csv '
          'size=450B',
    ]);
  });

  testWidgets('в папке экспорта остались старые файлы — перед новым '
      'экспортом удаляются все, пишется только новый', (tester) async {
    final h = await ExportHarness.open(tester);
    h.folder.createSync(recursive: true);
    File('${h.folder.path}${Platform.pathSeparator}milionchik_old_2025.csv')
        .writeAsStringSync('old');
    File(
      '${h.folder.path}${Platform.pathSeparator}milionchik_lichnyj_2026-10.csv',
    ).writeAsStringSync('stale');

    await h.share();

    expect(h.folderFiles, ['milionchik_lichnyj_2026-10.csv']);
    expect(h.sharer.contents.single.length, 389);
    expect(
      h.exportLogs(Level.FINE).map((r) => r.message),
      contains(matches(r'^export folder cleaned deleted=2 of 2 in \d+ms$')),
    );
  });
}
