import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milionchik/features/month/day_sheet.dart';
import 'package:milionchik/l10n/app_localizations.dart';
import 'package:shared/shared.dart';

Expense _expense({
  required LocalDate spentOn,
  required DateTime createdAt,
  String comment = '',
  String categoryId = 'c-cafe',
  int rubles = 100,
}) => Expense(
  id: 'e-${createdAt.microsecondsSinceEpoch}',
  budgetId: 'b-1',
  categoryId: categoryId,
  amount: Money.rubles(rubles),
  spentOn: spentOn,
  comment: comment,
  authorId: 'u-1',
  createdAt: createdAt,
  updatedAt: createdAt,
  updatedBy: 'u-1',
);

Category _category(String id, {bool system = false}) => Category(
  id: id,
  budgetId: 'b-1',
  name: system ? 'Другое' : 'Кафе',
  emoji: system ? '📦' : '☕',
  color: system ? null : CategoryColor.orange,
  sortOrder: system ? 99 : 1,
  isSystem: system,
  updatedAt: DateTime(2026, 8, 1),
  updatedBy: 'u-1',
);

String _rub(String digits) => '${digits.replaceAll(' ', nbsp)}$nbsp₽';

void main() {
  setUpAll(() => initializeDateFormatting('ru'));
  final l10n = lookupAppLocalizations(const Locale('ru'));
  final day = LocalDate(2026, 10, 17);
  final today = LocalDate(2026, 10, 19);

  group('время в подзаголовке (00-spec §7.2)', () {
    test('создана в день траты — время ЧЧ:ММ по часам телефона', () {
      final e = _expense(
        spentOn: day,
        createdAt: DateTime(2026, 10, 17, 9, 5),
        comment: 'Кофе с собой',
      );
      expect(expenseTime(e), '09:05');
      expect(expenseSubtitle(e), 'Кофе с собой · 09:05');
    });

    test('создана в другой день — без времени, даже за минуту до полуночи '
        'или через минуту после', () {
      for (final created in [
        DateTime(2026, 10, 16, 23, 59),
        DateTime(2026, 10, 18, 0, 1),
        DateTime(2026, 10, 19, 18, 40),
      ]) {
        final e = _expense(
          spentOn: day,
          createdAt: created,
          comment: 'Пятёрочка',
        );
        expect(expenseTime(e), isNull, reason: '$created');
        expect(expenseSubtitle(e), 'Пятёрочка', reason: '$created');
      }
    });

    test('граница дня: 00:00 и 23:59 того же дня — со временем', () {
      expect(
        expenseTime(_expense(spentOn: day, createdAt: DateTime(2026, 10, 17))),
        '00:00',
      );
      expect(
        expenseTime(
          _expense(spentOn: day, createdAt: DateTime(2026, 10, 17, 23, 59)),
        ),
        '23:59',
      );
    });

    test(
      'без комментария — только время, а без времени — подзаголовка нет',
      () {
        expect(
          expenseSubtitle(
            _expense(spentOn: day, createdAt: DateTime(2026, 10, 17, 18, 40)),
          ),
          '18:40',
        );
        expect(
          expenseSubtitle(
            _expense(spentOn: day, createdAt: DateTime(2026, 10, 19, 8)),
          ),
          isNull,
        );
      },
    );
  });

  group('итог и разница со средним (00-spec §7.3)', () {
    final expenses = [
      _expense(
        spentOn: day,
        createdAt: DateTime(2026, 10, 17, 13, 30),
        rubles: 890,
      ),
      _expense(
        spentOn: day,
        createdAt: DateTime(2026, 10, 17, 19, 10),
        rubles: 560,
      ),
    ];

    test('17 октября макета: 1 450 ₽, среднее 18 300 ₽ / 19 = 963,16 ₽, '
        '«2 траты · больше среднего на 487 ₽»', () {
      final summary = DaySummary.of(
        day: day,
        today: today,
        expenses: expenses,
        monthTotal: Money.rubles(18300),
      );
      expect(summary.count, 2);
      expect(summary.total, Money.rubles(1450));
      expect(summary.average, Money(96316));
      expect(summary.difference, Money(48684));
      expect(
        daySummaryLine(l10n, summary),
        '2 траты · больше среднего на ${_rub('487')}',
      );
    });

    test('день меньше среднего — «меньше среднего на …»', () {
      final summary = DaySummary.of(
        day: day,
        today: today,
        expenses: [expenses.first],
        monthTotal: Money.rubles(57000),
      );
      expect(summary.average, Money.rubles(3000));
      expect(
        daySummaryLine(l10n, summary),
        '1 трата · меньше среднего на ${_rub('2 110')}',
      );
    });

    test('разница меньше рубля — «столько же, сколько в среднем»', () {
      final summary = DaySummary.of(
        day: day,
        today: today,
        expenses: expenses,
        monthTotal: Money(1450 * 100 * 19 + 9),
      );
      expect(summary.difference!.abs.kopecks, lessThan(50));
      expect(
        daySummaryLine(l10n, summary),
        '2 траты · столько же, сколько в среднем',
      );
    });

    test('прошедший месяц — среднее за все его дни', () {
      final summary = DaySummary.of(
        day: LocalDate(2026, 9, 12),
        today: today,
        expenses: expenses,
        monthTotal: Money.rubles(30000),
      );
      expect(summary.average, Money.rubles(1000));
      expect(
        daySummaryLine(l10n, summary),
        '2 траты · больше среднего на ${_rub('450')}',
      );
    });

    test(
      'итог месяца неизвестен или в месяце трат нет — только число трат',
      () {
        final unknown = DaySummary.of(
          day: day,
          today: today,
          expenses: const [],
          monthTotal: null,
        );
        expect(unknown.total, Money.zero);
        expect(unknown.difference, isNull);
        expect(daySummaryLine(l10n, unknown), '0 трат');
        final empty = DaySummary.of(
          day: day,
          today: today,
          expenses: const [],
          monthTotal: Money.zero,
        );
        expect(empty.average, isNull);
        expect(daySummaryLine(l10n, empty), '0 трат');
      },
    );

    test('окончания: 1 трата, 2–4 траты, 5–20 трат, 21 трата, 22 траты, '
        '111 трат', () {
      expect(
        [
          for (final n in [1, 2, 4, 5, 11, 20, 21, 22, 25, 111])
            l10n.daySheetExpenses(n),
        ],
        [
          '1 трата',
          '2 траты',
          '4 траты',
          '5 трат',
          '11 трат',
          '20 трат',
          '21 трата',
          '22 траты',
          '25 трат',
          '111 трат',
        ],
      );
    });
  });

  test('заголовок — день недели и дата из intl ru с заглавной буквы', () {
    expect(dayTitle(LocalDate(2026, 10, 17)), 'Суббота, 17 октября');
    expect(dayTitle(LocalDate(2026, 10, 16)), 'Пятница, 16 октября');
    expect(dayTitle(LocalDate(2026, 1, 1)), 'Четверг, 1 января');
  });

  test('категория траты: своя по id, иначе системная «Другое», иначе нет', () {
    final cafe = _category('c-cafe');
    final other = _category('c-other', system: true);
    final e = _expense(spentOn: day, createdAt: DateTime(2026, 10, 17));
    expect(expenseCategory(e, [other, cafe]), cafe);
    final orphan = _expense(
      spentOn: day,
      createdAt: DateTime(2026, 10, 17),
      categoryId: 'c-deleted',
    );
    expect(expenseCategory(orphan, [cafe, other]), other);
    expect(expenseCategory(orphan, [cafe]), isNull);
  });
}
