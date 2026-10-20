import 'dart:convert';

import 'package:shared/shared.dart';
import 'package:test/test.dart';

CsvExpenseRow row(
  String date,
  int kopecks, {
  String category = 'Кафе',
  String comment = '',
  String budget = 'Личный',
  String author = 'Аня',
  int minute = 0,
}) {
  final spentOn = LocalDate.parse(date);
  return CsvExpenseRow(
    spentOn: spentOn,
    amount: Money(kopecks),
    category: category,
    comment: comment,
    budget: budget,
    author: author,
    createdAt: DateTime.utc(
      spentOn.year,
      spentOn.month,
      spentOn.day,
      12,
      minute,
    ),
  );
}

void main() {
  group('buildExpensesCsv', () {
    test('побайтово: BOM, «;», CRLF, порядок от старых к новым', () {
      final bytes = buildExpensesCsvBytes([
        row('2026-10-19', 64000, comment: 'Кофе; круассан', minute: 30),
        row(
          '2026-10-02',
          14990,
          category: 'Продукты',
          comment: 'Ёлка "на дачу"',
        ),
        row(
          '2026-10-19',
          12500000,
          category: 'Дом',
          comment: '=СУММ(1)',
          author: 'Дима',
          minute: 5,
        ),
      ]);

      const expected =
          '﻿'
          'Дата;Сумма;Категория;Комментарий;Бюджет;Кто добавил\r\n'
          '02.10.2026;149,90;Продукты;"Ёлка ""на дачу""";Личный;Аня\r\n'
          "19.10.2026;125000,00;Дом;'=СУММ(1);Личный;Дима\r\n"
          '19.10.2026;640,00;Кафе;"Кофе; круассан";Личный;Аня\r\n';
      expect(bytes, utf8.encode(expected));
      expect(bytes.sublist(0, 3), [0xEF, 0xBB, 0xBF]);
      expect(bytes.sublist(bytes.length - 2), [0x0D, 0x0A]);
      expect(utf8.decode(bytes).contains(RegExp('[^\r]\n')), isFalse);
    });

    test('без трат — только BOM и заголовок', () {
      expect(
        buildExpensesCsv(const []),
        '﻿Дата;Сумма;Категория;Комментарий;Бюджет;Кто добавил\r\n',
      );
    });
  });

  group('ячейки', () {
    test('экранирование кавычек, «;» и переводов строк', () {
      expect(csvTextCell('Кафе'), 'Кафе');
      expect(csvTextCell(''), '');
      expect(csvTextCell('a;b'), '"a;b"');
      expect(csvTextCell('say "hi"'), '"say ""hi"""');
      expect(csvTextCell('line\nnext'), '"line\nnext"');
      expect(csvTextCell('a\r\nb'), '"a\r\nb"');
    });

    test('защита от формул Excel', () {
      expect(csvTextCell('=SUM(1)'), "'=SUM(1)");
      expect(csvTextCell('+7 999 123'), "'+7 999 123");
      expect(csvTextCell('-50% скидка'), "'-50% скидка");
      expect(csvTextCell('@user'), "'@user");
      expect(csvTextCell('\tx'), "'\tx");
      expect(csvTextCell('=a;b'), '"\'=a;b"');
      expect(csvTextCell('a=b'), 'a=b');
    });

    test('дата dd.MM.yyyy и сумма всегда с копейками', () {
      expect(csvDate(LocalDate(2026, 3, 5)), '05.03.2026');
      expect(csvAmount(const Money.rubles(640)), '640,00');
      expect(csvAmount(const Money(14990)), '149,90');
      expect(csvAmount(const Money.rubles(12500)), '12500,00');
      expect(csvAmount(const Money(5)), '0,05');
      expect(csvAmount(const Money(-14990)), '-149,90');
    });
  });

  group('имя файла', () {
    test('как в макете: milionchik_lichnyj_2026-10.csv', () {
      expect(
        csvFileName('Личный', MonthPeriod(YearMonth(2026, 10))),
        'milionchik_lichnyj_2026-10.csv',
      );
    });

    test('год и свои даты', () {
      expect(
        csvFileName('Семья', YearPeriod(2026)),
        'milionchik_semya_2026.csv',
      );
      expect(
        csvFileName(
          'Семья',
          RangePeriod(LocalDate(2026, 10, 1), LocalDate(2026, 10, 19)),
        ),
        'milionchik_semya_2026-10-01_2026-10-19.csv',
      );
    });

    test('транслитерация', () {
      expect(transliterateForFileName('Семья и друзья'), 'semya_i_druzya');
      expect(
        transliterateForFileName('Ёжик Щука Эхо Юла Ягода Цех Хор Шар Чай Ъ'),
        'yozhik_shhuka_eho_yula_yagoda_ceh_hor_shar_chaj',
      );
      expect(transliterateForFileName('Дом-2'), 'dom2');
      expect(transliterateForFileName('Trip 2026!'), 'trip_2026');
      expect(transliterateForFileName('  🏠  Дача  '), 'dacha');
      expect(transliterateForFileName('🏠'), 'budget');
      expect(transliterateForFileName('   '), 'budget');
    });
  });

  group('периоды', () {
    test('границы', () {
      final month = MonthPeriod(YearMonth(2028, 2));
      expect(month.from, LocalDate(2028, 2, 1));
      expect(month.to, LocalDate(2028, 2, 29));
      final year = YearPeriod(2026);
      expect(year.from, LocalDate(2026, 1, 1));
      expect(year.to, LocalDate(2026, 12, 31));
      final range = RangePeriod(LocalDate(2026, 10, 5), LocalDate(2026, 10, 5));
      expect(range.fileNamePart, '2026-10-05_2026-10-05');
    });

    test('неверные периоды — ошибка', () {
      expect(
        () => RangePeriod(LocalDate(2026, 10, 2), LocalDate(2026, 10, 1)),
        throwsArgumentError,
      );
      expect(() => YearPeriod(0), throwsRangeError);
    });
  });
}
