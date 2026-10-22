import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milionchik/features/export/export_screen.dart';
import 'package:milionchik/ui/components/chip.dart';

import 'export_fixture.dart';

AppChip _chip(WidgetTester tester, String label) => tester.widget<AppChip>(
  find.ancestor(
    of: find.descendant(
      of: find.byType(ExportScreen),
      matching: find.text(label),
    ),
    matching: find.byType(AppChip),
  ),
);

Future<void> _enterRange(
  WidgetTester tester,
  ExportHarness h,
  String from,
  String to,
) async {
  await h.tapText('Свои даты');
  expect(find.byType(DateRangePickerDialog), findsOneWidget);
  await tester.tap(find.byIcon(Icons.edit_outlined));
  await tester.pumpAndSettle();
  final fields = find.descendant(
    of: find.byType(DateRangePickerDialog),
    matching: find.byType(TextField),
  );
  await tester.enterText(fields.at(0), from);
  await tester.enterText(fields.at(1), to);
  await tester.tap(find.text('ОК'));
  await h.settle();
}

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testWidgets('по умолчанию выбран текущий месяц; «2026 год» — файл '
      'milionchik_lichnyj_2026.csv с сентябрём, без 2025 года', (tester) async {
    final h = await ExportHarness.open(tester);

    expect(_chip(tester, 'Октябрь 2026').selected, isTrue);
    expect(_chip(tester, '2026 год').selected, isFalse);
    expect(_chip(tester, 'Свои даты').selected, isFalse);

    await h.tapText('2026 год');

    expect(_chip(tester, 'Октябрь 2026').selected, isFalse);
    expect(_chip(tester, '2026 год').selected, isTrue);
    expect(h.fileCardText, 'milionchik_lichnyj_2026.csv | 5 трат · 13 654 ₽');

    await h.share();
    final lines = utf8.decode(h.sharer.contents.single).split('\r\n');
    expect(lines, hasLength(7));
    expect(lines[1], '30.09.2026;300,00;Кафе;Сентябрь;Личный;Я');
    expect(lines.where((l) => l.contains('2025')), isEmpty);

    await h.tapText('Октябрь 2026');
    expect(
      h.fileCardText,
      'milionchik_lichnyj_2026-10.csv | 4 траты · 13 354 ₽',
    );
  });

  testWidgets('свои даты 01.09.2026 – 30.09.2026: чип с датами, файл с '
      'датами в имени и одной тратой сентября', (tester) async {
    final h = await ExportHarness.open(tester);

    await _enterRange(tester, h, '01.09.2026', '30.09.2026');

    expect(find.byType(DateRangePickerDialog), findsNothing);
    expect(_chip(tester, '01.09.2026 – 30.09.2026').selected, isTrue);
    expect(_chip(tester, 'Октябрь 2026').selected, isFalse);
    expect(
      h.fileCardText,
      'milionchik_lichnyj_2026-09-01_2026-09-30.csv | 1 трата · 300 ₽',
    );

    await h.share();
    expect(
      h.sharer.paths.single,
      endsWith('milionchik_lichnyj_2026-09-01_2026-09-30.csv'),
    );
    expect(h.sharer.contents.single, [
      0xEF,
      0xBB,
      0xBF,
      ...utf8.encode(
        'Дата;Сумма;Категория;Комментарий;Бюджет;Кто добавил\r\n'
        '30.09.2026;300,00;Кафе;Сентябрь;Личный;Я\r\n',
      ),
    ]);

    await h.tapText('2026 год');
    expect(_chip(tester, 'Свои даты').selected, isFalse);
  });

  testWidgets('выбор дат отменён — период остаётся прежним', (tester) async {
    final h = await ExportHarness.open(tester);

    await h.tapText('Свои даты');
    expect(find.byType(DateRangePickerDialog), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close));
    await h.settle();

    expect(find.byType(DateRangePickerDialog), findsNothing);
    expect(_chip(tester, 'Октябрь 2026').selected, isTrue);
    expect(_chip(tester, 'Свои даты').selected, isFalse);
    expect(
      h.fileCardText,
      'milionchik_lichnyj_2026-10.csv | 4 траты · 13 354 ₽',
    );
  });
}
