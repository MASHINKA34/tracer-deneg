import 'package:flutter_test/flutter_test.dart';
import 'package:milionchik/features/recurring/recurring_editor_controller.dart';
import 'package:shared/shared.dart';

RecurringRule _rule({required int day, required YearMonth from}) =>
    RecurringRule(
      id: 'rule-1',
      budgetId: 'budget-1',
      categoryId: 'cat-1',
      title: 'Спортзал',
      amount: Money.rubles(2900),
      dayOfMonth: day,
      startMonth: from,
      createdAt: DateTime.utc(2026, 9, 1),
      updatedAt: DateTime.utc(2026, 9, 1),
      updatedBy: 'user-1',
    );

void main() {
  final today = LocalDate(2026, 10, 19);
  final october = YearMonth(2026, 10);
  final november = YearMonth(2026, 11);
  final september = YearMonth(2026, 9);

  group('firstChargeOfNewRule', () {
    test('день ещё не прошёл — в этом месяце, сегодня — сегодня, прошёл — '
        'в следующем', () {
      expect(firstChargeOfNewRule(20, today), LocalDate(2026, 10, 20));
      expect(firstChargeOfNewRule(19, today), today);
      expect(firstChargeOfNewRule(18, today), LocalDate(2026, 11, 18));
    });

    test('31-е: в октябре 31-го, 5 ноября — 30 ноября, 29 января — 31 '
        'января, 1 февраля — 28 февраля', () {
      expect(firstChargeOfNewRule(31, today), LocalDate(2026, 10, 31));
      expect(
        firstChargeOfNewRule(31, LocalDate(2026, 11, 5)),
        LocalDate(2026, 11, 30),
      );
      expect(
        firstChargeOfNewRule(31, LocalDate(2027, 1, 29)),
        LocalDate(2027, 1, 31),
      );
      expect(
        firstChargeOfNewRule(31, LocalDate(2027, 2, 1)),
        LocalDate(2027, 2, 28),
      );
    });

    test('31 декабря, 10-е — 10 января следующего года', () {
      expect(
        firstChargeOfNewRule(10, LocalDate(2026, 12, 31)),
        LocalDate(2027, 1, 10),
      );
    });
  });

  group('startMonthAfterDayChange', () {
    test('день тот же — месяц начала не меняется', () {
      expect(
        startMonthAfterDayChange(_rule(day: 24, from: october), 24, today),
        isNull,
      );
    });

    test('в этом месяце трата ещё не была положена: новый день уже прошёл — '
        'старт переносится на следующий месяц, сегодня или впереди — '
        'остаётся', () {
      final rule = _rule(day: 24, from: october);
      expect(startMonthAfterDayChange(rule, 5, today), november);
      expect(startMonthAfterDayChange(rule, 19, today), isNull);
      expect(startMonthAfterDayChange(rule, 28, today), isNull);
    });

    test('старт в будущем месяце: новый день ещё впереди — старт '
        'возвращается на этот месяц', () {
      final rule = _rule(day: 5, from: november);
      expect(startMonthAfterDayChange(rule, 25, today), october);
      expect(startMonthAfterDayChange(rule, 19, today), october);
      expect(startMonthAfterDayChange(rule, 10, today), isNull);
    });

    test('трата этого месяца уже положена или правило старше — месяц '
        'начала не трогаем', () {
      expect(
        startMonthAfterDayChange(_rule(day: 12, from: october), 25, today),
        isNull,
      );
      expect(
        startMonthAfterDayChange(_rule(day: 24, from: september), 5, today),
        isNull,
      );
    });
  });

  group('RecurringDraft', () {
    final rule = _rule(day: 12, from: october);

    test('изменённые поля: только отличающиеся от правила, название без '
        'пробелов по краям', () {
      expect(const RecurringDraft().changedFields(rule), isEmpty);
      expect(
        RecurringDraft(
          title: '  Спортзал ',
          amount: Money.rubles(2900),
          categoryId: 'cat-1',
          day: 12,
        ).changedFields(rule),
        isEmpty,
      );
      expect(
        RecurringDraft(
          title: 'Фитнес',
          amount: Money.rubles(3200),
          categoryId: 'cat-2',
          day: 25,
        ).changedFields(rule),
        RecurringField.values,
      );
    });

    test('у новой: день по умолчанию сегодняшний, сумма 0, категории нет; '
        'ошибки видны только после «Сохранить», пустое название — после '
        'ввода', () {
      const draft = RecurringDraft();
      expect(draft.dayOf(null, today), 19);
      expect(draft.amountOf(null), Money.zero);
      expect(draft.categoryOf(null), isNull);
      expect(draft.errorCodes(null), [
        'recurring_title_empty',
        'amount_empty',
        'category_missing',
      ]);
      expect(draft.visibleTitleError(null), isNull);
      expect(draft.visibleAmountError(null), isNull);
      expect(draft.visibleCategoryMissing(null), isFalse);
      expect(
        draft.copyWith(title: '').visibleTitleError(null),
        ValidationError.recurringTitleEmpty,
      );
      final submitted = draft.copyWith(submitted: true);
      expect(
        submitted.visibleTitleError(null),
        ValidationError.recurringTitleEmpty,
      );
      expect(submitted.visibleAmountError(null), ValidationError.amountEmpty);
      expect(submitted.visibleCategoryMissing(null), isTrue);
      expect(
        draft.copyWith(title: 'я' * 41).visibleTitleError(null),
        ValidationError.recurringTitleTooLong,
      );
    });
  });
}
