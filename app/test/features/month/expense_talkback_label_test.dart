import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milionchik/features/month/day_sheet.dart';
import 'package:milionchik/l10n/app_localizations.dart';
import 'package:shared/shared.dart';

Expense _expense({
  required Money amount,
  String comment = '',
  DateTime? createdAt,
}) {
  final created = createdAt ?? DateTime(2026, 10, 19, 18, 40);
  return Expense(
    id: 'e-1',
    budgetId: 'b-1',
    categoryId: 'c-food',
    amount: amount,
    spentOn: LocalDate(2026, 10, 19),
    comment: comment,
    authorId: 'u-1',
    createdAt: created,
    updatedAt: created,
    updatedBy: 'u-1',
  );
}

void main() {
  setUpAll(() => initializeDateFormatting('ru'));
  final l10n = lookupAppLocalizations(const Locale('ru'));

  group('сумма траты словами для TalkBack', () {
    test('рубли с окончанием по числу и неразрывным пробелом в разрядах', () {
      expect(spokenAmount(l10n, Money.rubles(1)), '1 рубль');
      expect(spokenAmount(l10n, Money.rubles(2)), '2 рубля');
      expect(spokenAmount(l10n, Money.rubles(5)), '5 рублей');
      expect(spokenAmount(l10n, Money.rubles(11)), '11 рублей');
      expect(spokenAmount(l10n, Money.rubles(21)), '21 рубль');
      expect(spokenAmount(l10n, Money.rubles(640)), '640 рублей');
      expect(spokenAmount(l10n, Money.rubles(1100)), '1${nbsp}100 рублей');
      expect(
        spokenAmount(l10n, Money.rubles(10000000)),
        '10${nbsp}000${nbsp}000 рублей',
      );
    });

    test('копейки — только если не ноль, без «0 рублей»', () {
      expect(spokenAmount(l10n, Money.rubles(149, 90)), '149 рублей 90 копеек');
      expect(spokenAmount(l10n, Money.rubles(21, 2)), '21 рубль 2 копейки');
      expect(spokenAmount(l10n, Money.rubles(3, 1)), '3 рубля 1 копейка');
      expect(spokenAmount(l10n, const Money(1)), '1 копейка');
      expect(spokenAmount(l10n, const Money(50)), '50 копеек');
      expect(spokenAmount(l10n, Money.rubles(640, 0)), '640 рублей');
    });
  });

  group('подпись строки траты: категория, комментарий, время, сумма', () {
    test('как на 7:7 — с комментарием и временем создания в тот же день', () {
      expect(
        expenseLabel(
          l10n,
          _expense(amount: Money.rubles(640), comment: 'Пятёрочка'),
          'Продукты',
        ),
        'Продукты, Пятёрочка, 18:40, 640 рублей',
      );
    });

    test('без комментария — категория, время и сумма', () {
      expect(
        expenseLabel(
          l10n,
          _expense(
            amount: Money.rubles(149, 90),
            createdAt: DateTime(2026, 10, 19, 9, 5),
          ),
          'Кафе',
        ),
        'Кафе, 09:05, 149 рублей 90 копеек',
      );
    });

    test('создана в другой день — без времени', () {
      expect(
        expenseLabel(
          l10n,
          _expense(
            amount: Money.rubles(250),
            comment: 'Метро, 2 поездки',
            createdAt: DateTime(2026, 10, 20, 8),
          ),
          'Транспорт',
        ),
        'Транспорт, Метро, 2 поездки, 250 рублей',
      );
    });
  });
}
