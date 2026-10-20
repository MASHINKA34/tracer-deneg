import 'dart:convert';
import 'dart:typed_data';

import '../money/money.dart';
import '../time/local_date.dart';
import '../time/year_month.dart';

/// Строка экспорта: трата с уже подставленными названиями.
final class CsvExpenseRow {
  const CsvExpenseRow({
    required this.spentOn,
    required this.amount,
    required this.category,
    required this.comment,
    required this.budget,
    required this.author,
    required this.createdAt,
  });

  final LocalDate spentOn;
  final Money amount;
  final String category;
  final String comment;
  final String budget;

  /// Кто добавил (имя участника; для удалённого — текст из приложения).
  final String author;

  /// Момент создания — порядок трат внутри дня.
  final DateTime createdAt;
}

/// Заголовок CSV (00-spec §12 п.13).
const List<String> csvHeader = [
  'Дата',
  'Сумма',
  'Категория',
  'Комментарий',
  'Бюджет',
  'Кто добавил',
];

const String _bom = '﻿';
const String _crlf = '\r\n';
const String _separator = ';';

/// Начало ячейки, которое Excel выполнит как формулу.
const Set<String> _formulaStarts = {'=', '+', '-', '@', '\t', '\r'};

/// Текстовая ячейка: защита от формул (апостроф перед `= + - @`, табуляцией
/// и CR в начале) и кавычки, если внутри `;`, `"`, CR или LF (кавычки
/// внутри удваиваются).
String csvTextCell(String value) {
  var text = value;
  if (text.isNotEmpty && _formulaStarts.contains(text[0])) text = "'$text";
  if (text.contains(RegExp('[;"\r\n]'))) {
    text = '"${text.replaceAll('"', '""')}"';
  }
  return text;
}

/// Дата `dd.MM.yyyy`.
String csvDate(LocalDate date) =>
    '${date.day.toString().padLeft(2, '0')}.'
    '${date.month.toString().padLeft(2, '0')}.'
    '${date.year.toString().padLeft(4, '0')}';

/// Сумма с копейками всегда, без разделителя тысяч: `12500,00`.
String csvAmount(Money amount) =>
    '${amount.isNegative ? '-' : ''}${amount.kopecks.abs() ~/ 100},'
    '${amount.kopecksPart.toString().padLeft(2, '0')}';

/// Текст CSV экспорта: BOM, разделитель `;`, строки через CRLF (и после
/// последней), траты от старых к новым, внутри дня — по моменту создания.
String buildExpensesCsv(Iterable<CsvExpenseRow> rows) {
  final sorted = rows.toList()
    ..sort((a, b) {
      final byDate = a.spentOn.compareTo(b.spentOn);
      return byDate != 0 ? byDate : a.createdAt.compareTo(b.createdAt);
    });
  final buffer = StringBuffer(_bom)
    ..write(csvHeader.join(_separator))
    ..write(_crlf);
  for (final row in sorted) {
    buffer
      ..write(
        [
          csvDate(row.spentOn),
          csvAmount(row.amount),
          csvTextCell(row.category),
          csvTextCell(row.comment),
          csvTextCell(row.budget),
          csvTextCell(row.author),
        ].join(_separator),
      )
      ..write(_crlf);
  }
  return buffer.toString();
}

/// Байты файла экспорта: UTF-8, начинаются с BOM `EF BB BF`.
Uint8List buildExpensesCsvBytes(Iterable<CsvExpenseRow> rows) =>
    utf8.encode(buildExpensesCsv(rows));

/// Период экспорта: месяц, год или свои даты.
sealed class ExportPeriod {
  const ExportPeriod();

  /// Первый день периода.
  LocalDate get from;

  /// Последний день периода (включительно).
  LocalDate get to;

  /// Часть имени файла: `2026-10`, `2026`, `2026-10-01_2026-10-19`.
  String get fileNamePart;
}

/// Месяц.
final class MonthPeriod extends ExportPeriod {
  const MonthPeriod(this.month);

  final YearMonth month;

  @override
  LocalDate get from => month.firstDay;

  @override
  LocalDate get to => month.lastDay;

  @override
  String get fileNamePart => '$month';
}

/// Год.
final class YearPeriod extends ExportPeriod {
  YearPeriod(this.year) {
    RangeError.checkValueInInterval(year, 1, 9999, 'year');
  }

  final int year;

  @override
  LocalDate get from => LocalDate(year, 1, 1);

  @override
  LocalDate get to => LocalDate(year, 12, 31);

  @override
  String get fileNamePart => year.toString().padLeft(4, '0');
}

/// Свои даты (включительно); [from] не позже [to].
final class RangePeriod extends ExportPeriod {
  RangePeriod(this.from, this.to) {
    if (from > to) {
      throw ArgumentError.value(to, 'to', 'is before from=$from');
    }
  }

  @override
  final LocalDate from;

  @override
  final LocalDate to;

  @override
  String get fileNamePart => '${from}_$to';
}

const Map<String, String> _translit = {
  'а': 'a', 'б': 'b', 'в': 'v', 'г': 'g', 'д': 'd', 'е': 'e', 'ё': 'yo', //
  'ж': 'zh', 'з': 'z', 'и': 'i', 'й': 'j', 'к': 'k', 'л': 'l', 'м': 'm', //
  'н': 'n', 'о': 'o', 'п': 'p', 'р': 'r', 'с': 's', 'т': 't', 'у': 'u', //
  'ф': 'f', 'х': 'h', 'ц': 'c', 'ч': 'ch', 'ш': 'sh', 'щ': 'shh', 'ъ': '', //
  'ы': 'y', 'ь': '', 'э': 'e', 'ю': 'yu', 'я': 'ya',
};

final RegExp _latinOrDigit = RegExp(r'[a-z0-9]');
final RegExp _separatorChar = RegExp(r'[\s_]');
final RegExp _repeatedUnderscores = RegExp(r'_+');

/// Название бюджета латиницей для имени файла: «Личный» → `lichnyj`,
/// «Семья и друзья» → `semya_i_druzya`. Пробелы → `_`, прочие знаки
/// убираются; ничего не осталось — `budget`.
String transliterateForFileName(String name) {
  final buffer = StringBuffer();
  for (final char in name.toLowerCase().split('')) {
    final mapped = _translit[char];
    if (mapped != null) {
      buffer.write(mapped);
    } else if (_latinOrDigit.hasMatch(char)) {
      buffer.write(char);
    } else if (_separatorChar.hasMatch(char)) {
      buffer.write('_');
    }
  }
  final slug = buffer
      .toString()
      .replaceAll(_repeatedUnderscores, '_')
      .replaceAll(RegExp(r'^_|_$'), '');
  return slug.isEmpty ? 'budget' : slug;
}

/// Имя файла экспорта: `milionchik_lichnyj_2026-10.csv`.
String csvFileName(String budgetName, ExportPeriod period) =>
    'milionchik_${transliterateForFileName(budgetName)}_'
    '${period.fileNamePart}.csv';
