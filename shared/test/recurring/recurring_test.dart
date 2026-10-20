import 'package:shared/shared.dart';
import 'package:test/test.dart';

const ruleId = '0b5c3f8e-1111-4222-8333-444455556666';

RecurringRule rule({int day = 24, YearMonth? start, DateTime? deletedAt}) =>
    RecurringRule(
      id: ruleId,
      budgetId: 'b1',
      categoryId: 'c1',
      title: 'Интернет',
      amount: const Money.rubles(650),
      dayOfMonth: day,
      startMonth: start ?? YearMonth(2026, 7),
      createdAt: DateTime.utc(2026, 7, 1),
      updatedAt: DateTime.utc(2026, 7, 1),
      updatedBy: 'u1',
      deletedAt: deletedAt,
    );

void main() {
  group('chargeDay: min(D, дней в месяце)', () {
    test('регулярная на 31-е в феврале високосного и обычного года', () {
      expect(chargeDay(31, YearMonth(2028, 2)), 29);
      expect(chargeDay(31, YearMonth(2026, 2)), 28);
      expect(chargeDate(31, YearMonth(2028, 2)), LocalDate(2028, 2, 29));
      expect(chargeDate(31, YearMonth(2026, 2)), LocalDate(2026, 2, 28));
    });

    test('короткий месяц и обычный день', () {
      expect(chargeDay(31, YearMonth(2026, 4)), 30);
      expect(chargeDay(29, YearMonth(2026, 2)), 28);
      expect(chargeDay(15, YearMonth(2026, 2)), 15);
      expect(chargeDay(31, YearMonth(2026, 10)), 31);
    });

    test('день вне 1–31 — ошибка', () {
      expect(() => chargeDay(0, YearMonth(2026, 1)), throwsRangeError);
      expect(() => chargeDay(32, YearMonth(2026, 1)), throwsRangeError);
    });
  });

  group('recurringExpenseId: UUID v5', () {
    test('эталоны для фиксированного namespace проекта', () {
      // Посчитано независимо: Python uuid.uuid5(namespace, "<ruleId>:<YYYY-MM>").
      expect(
        recurringExpenseId(ruleId, YearMonth(2026, 7)),
        '5bda2760-e523-50a9-adf6-5badce38ac19',
      );
      expect(
        recurringExpenseId(ruleId, YearMonth(2026, 10)),
        'da638766-e981-56da-ad82-fab7753cbd52',
      );
    });

    test('одинаков при повторе, разный для разных месяцев', () {
      final a = recurringExpenseId(ruleId, YearMonth(2026, 8));
      expect(recurringExpenseId(ruleId, YearMonth(2026, 8)), a);
      expect(recurringExpenseId(ruleId, YearMonth(2026, 9)), isNot(a));
      expect(isUuid(a), isTrue);
      expect(a[14], '5');
    });
  });

  group('dueMonths', () {
    test('догонялка за 3 пропущенных месяца', () {
      expect(
        dueMonths(
          startMonth: YearMonth(2026, 7),
          dayOfMonth: 24,
          today: LocalDate(2026, 10, 19),
        ),
        [YearMonth(2026, 7), YearMonth(2026, 8), YearMonth(2026, 9)],
      );
    });

    test('текущий месяц — когда сегодня ≥ дня списания', () {
      expect(
        dueMonths(
          startMonth: YearMonth(2026, 10),
          dayOfMonth: 24,
          today: LocalDate(2026, 10, 24),
        ),
        [YearMonth(2026, 10)],
      );
      expect(
        dueMonths(
          startMonth: YearMonth(2026, 10),
          dayOfMonth: 24,
          today: LocalDate(2026, 10, 23),
        ),
        isEmpty,
      );
    });

    test('31-е в феврале списывается 28-го', () {
      expect(
        dueMonths(
          startMonth: YearMonth(2026, 2),
          dayOfMonth: 31,
          today: LocalDate(2026, 2, 28),
        ),
        [YearMonth(2026, 2)],
      );
    });

    test('месяц начала в будущем — ничего', () {
      expect(
        dueMonths(
          startMonth: YearMonth(2026, 11),
          dayOfMonth: 1,
          today: LocalDate(2026, 10, 31),
        ),
        isEmpty,
      );
    });
  });

  group('planRecurringExpenses', () {
    final today = LocalDate(2026, 10, 19);

    test('создать недостающие: id, месяц, дата', () {
      final planned = planRecurringExpenses(
        rule(),
        today,
        existingExpenseIds: const {},
      );
      expect(planned.map((p) => p.spentOn), [
        LocalDate(2026, 7, 24),
        LocalDate(2026, 8, 24),
        LocalDate(2026, 9, 24),
      ]);
      expect(planned.first.id, '5bda2760-e523-50a9-adf6-5badce38ac19');
      expect(planned.first.month, YearMonth(2026, 7));
    });

    test('уже созданные и удалённые пользователем не пересоздаются', () {
      final deletedByUser = recurringExpenseId(ruleId, YearMonth(2026, 8));
      final planned = planRecurringExpenses(
        rule(),
        today,
        existingExpenseIds: {deletedByUser},
      );
      expect(planned.map((p) => p.month), [
        YearMonth(2026, 7),
        YearMonth(2026, 9),
      ]);
    });

    test('повторный запуск после создания — пусто (идемпотентно)', () {
      final first = planRecurringExpenses(
        rule(),
        today,
        existingExpenseIds: const {},
      );
      final again = planRecurringExpenses(
        rule(),
        today,
        existingExpenseIds: {for (final p in first) p.id},
      );
      expect(again, isEmpty);
      // На другом телефоне — те же id.
      expect(
        planRecurringExpenses(rule(), today, existingExpenseIds: const {}),
        first,
      );
    });

    test('удалённое правило новых трат не создаёт', () {
      expect(
        planRecurringExpenses(
          rule(deletedAt: DateTime.utc(2026, 9, 1)),
          today,
          existingExpenseIds: const {},
        ),
        isEmpty,
      );
    });

    test('равенство и текст', () {
      final a = planRecurringExpenses(rule(), today, existingExpenseIds: {});
      expect(a.first.hashCode, a.first.hashCode);
      expect(a.first.toString(), contains('2026-07'));
    });
  });

  group('startMonthForNewRule', () {
    test('день ещё не прошёл — текущий месяц, прошёл — следующий', () {
      expect(
        startMonthForNewRule(24, LocalDate(2026, 10, 19)),
        YearMonth(2026, 10),
      );
      expect(
        startMonthForNewRule(24, LocalDate(2026, 10, 25)),
        YearMonth(2026, 11),
      );
      expect(
        startMonthForNewRule(24, LocalDate(2026, 12, 25)),
        YearMonth(2027, 1),
      );
    });

    test('создана в сам день списания — первая трата сегодня', () {
      final today = LocalDate(2026, 10, 24);
      final start = startMonthForNewRule(24, today);
      expect(start, YearMonth(2026, 10));
      expect(dueMonths(startMonth: start, dayOfMonth: 24, today: today), [
        YearMonth(2026, 10),
      ]);
    });

    test('31-е и 28 февраля — ещё текущий месяц', () {
      expect(
        startMonthForNewRule(31, LocalDate(2026, 2, 28)),
        YearMonth(2026, 2),
      );
    });
  });

  group('nextChargeDate', () {
    test('«Скоро: каждое 24-е · через 5 дней»', () {
      final today = LocalDate(2026, 10, 19);
      final next = nextChargeDate(
        startMonth: YearMonth(2026, 7),
        dayOfMonth: 24,
        today: today,
      );
      expect(next, LocalDate(2026, 10, 24));
      expect(today.daysUntil(next), 5);
    });

    test('в день списания и после — следующий месяц', () {
      expect(
        nextChargeDate(
          startMonth: YearMonth(2026, 7),
          dayOfMonth: 24,
          today: LocalDate(2026, 10, 24),
        ),
        LocalDate(2026, 11, 24),
      );
      expect(
        nextChargeDate(
          startMonth: YearMonth(2025, 11),
          dayOfMonth: 31,
          today: LocalDate(2026, 1, 31),
        ),
        LocalDate(2026, 2, 28),
      );
    });

    test('«Первая трата появится 12 ноября»', () {
      final today = LocalDate(2026, 10, 19);
      final start = startMonthForNewRule(12, today);
      expect(start, YearMonth(2026, 11));
      expect(
        nextChargeDate(startMonth: start, dayOfMonth: 12, today: today),
        LocalDate(2026, 11, 12),
      );
    });
  });
}
