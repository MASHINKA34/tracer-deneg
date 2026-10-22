import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milionchik/data/db/app_database.dart';

import 'export_fixture.dart';

const String _expectedOctober =
    'Дата;Сумма;Категория;Комментарий;Бюджет;Кто добавил\r\n'
    '02.10.2026;64,00;Транспорт;Метро;Личный;Я\r\n'
    '05.10.2026;640,00;Кафе;;Личный;Я\r\n'
    '05.10.2026;149,90;Продукты;"Хлеб; молоко ""Простоквашино""";Личный;Я\r\n'
    "19.10.2026;12500,00;Развлечения;'=Ёлка;Личный;Я\r\n";

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testWidgets('октябрь: файл milionchik_lichnyj_2026-10.csv побайтово — BOM, '
      '«;», CRLF, траты по дате и времени создания, кавычки и апостроф перед '
      '«=», сентябрь и 2025 год не попали', (tester) async {
    final h = await ExportHarness.open(tester);

    expect(
      h.fileCardText,
      'milionchik_lichnyj_2026-10.csv | 4 траты · 13 354 ₽',
    );
    expect(h.shareEnabled, isTrue);

    await h.share();

    expect(h.sharer.paths, hasLength(1));
    expect(
      h.sharer.paths.single,
      endsWith('export${Platform.pathSeparator}milionchik_lichnyj_2026-10.csv'),
    );
    final bytes = h.sharer.contents.single;
    expect(bytes.sublist(0, 3), [0xEF, 0xBB, 0xBF]);
    expect(bytes, [0xEF, 0xBB, 0xBF, ...utf8.encode(_expectedOctober)]);
    final text = utf8.decode(bytes);
    expect(text.split('\r\n'), hasLength(6));
    expect(text.replaceAll('\r\n', ''), isNot(contains('\n')));
    expect(h.folderFiles, ['milionchik_lichnyj_2026-10.csv']);
  });

  testWidgets('пустой период: «0 трат · 0 ₽», «Поделиться файлом» '
      'неактивна, под ней подпись, нажатие ничего не делает', (tester) async {
    final h = await ExportHarness.open(
      tester,
      seed: (AppDatabase db) async {
        await seedSmallExport(db);
        await db.delete(db.expenses).go();
      },
    );

    expect(h.fileCardText, 'milionchik_lichnyj_2026-10.csv | 0 трат · 0 ₽');
    expect(h.shareEnabled, isFalse);
    expect(find.text('За этот период трат нет — выгружать нечего'), findsOne);

    await tester.tap(h.shareButton);
    await h.settle();

    expect(h.sharer.paths, isEmpty);
    expect(h.folderFiles, isEmpty);
  });
}
