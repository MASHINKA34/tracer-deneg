import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import 'repository_harness.dart';

void main() {
  late RepositoryHarness h;
  late SeededBudget b;

  setUp(() async {
    h = RepositoryHarness();
    b = await h.seedBudget();
  });

  tearDown(() => h.dispose());

  test(
    'запись траты — debug: сущность, id, операция, сумма, outbox и мс',
    () async {
      final expense = await h.expenses.create(
        budgetId: b.id,
        categoryId: b.byName('Кафе').id,
        amount: const Money.rubles(640),
        spentOn: LocalDate(2026, 10, 20),
        comment: 'Секретный кофе',
      );
      await h.expenses.delete(expense.id);

      final debug = h.repoLogs(Level.FINE).map((r) => r.message).toList();
      expect(
        debug,
        contains(
          'expense create id=${expense.id} budget=${b.id} '
          'category=${b.byName('Кафе').id} amount=64000 outbox=upsert#1 in '
          '${_ms(debug, 'expense create')}ms',
        ),
      );
      expect(
        debug,
        contains(
          matches(
            RegExp(
              '^expense delete id=${expense.id} budget=${b.id} '
              r'outbox=delete#2 notBefore=2026-10-20T09:00:05\.000Z in \d+ms$',
            ),
          ),
        ),
      );
    },
  );

  test('тексты, названия и суммы не попадают в info и выше', () async {
    final expense = await h.expenses.create(
      budgetId: b.id,
      categoryId: b.byName('Кафе').id,
      amount: const Money.rubles(640),
      spentOn: LocalDate(2026, 10, 20),
      comment: 'Секретный кофе',
    );
    await h.categories.create(
      budgetId: b.id,
      name: 'Тайная',
      emoji: '🔒',
      color: CategoryColor.rose,
    );
    await h.recurring.create(
      budgetId: b.id,
      categoryId: b.other.id,
      title: 'Тайный абонемент',
      amount: const Money.rubles(1234),
      dayOfMonth: 7,
      startMonth: YearMonth(2026, 11),
    );
    await h.expenses.delete(expense.id);
    await h.expenses.undoDelete(expense.id);
    await expectLater(
      h.expenses.create(
        budgetId: b.id,
        categoryId: b.other.id,
        amount: const Money.rubles(1),
        spentOn: LocalDate(2026, 10, 20),
        comment: 'Секрет ' * 20,
      ),
      throwsA(anything),
    );

    final all = h.repoLogs().map((r) => r.message).join('\n');
    for (final secret in ['Секрет', 'Тайн', 'кофе', 'Кафе']) {
      expect(all, isNot(contains(secret)), reason: secret);
    }
    final visible = h
        .repoLogs()
        .where((r) => r.level >= Level.INFO)
        .map((r) => r.message)
        .join('\n');
    for (final amount in ['64000', '123400', 'amount=']) {
      expect(visible, isNot(contains(amount)), reason: amount);
    }
  });

  test('отклонённая операция — warn с сущностью, id и кодом', () async {
    await expectLater(h.categories.delete(b.other.id), throwsA(anything));
    await expectLater(
      h.expenses.update('missing', amount: const Money.rubles(1)),
      throwsA(anything),
    );

    final warnings = h.repoLogs(Level.WARNING).map((r) => r.message).toList();
    expect(warnings, [
      matches(
        RegExp(
          '^category delete rejected id=${b.other.id} '
          r'reason=system_category after \d+ms$',
        ),
      ),
      matches(
        RegExp(
          r'^expense update rejected id=missing reason=not_found '
          r'after \d+ms$',
        ),
      ),
    ]);
  });
}

String _ms(List<String> lines, String prefix) {
  final line = lines.firstWhere((l) => l.startsWith(prefix));
  return RegExp(r'in (\d+)ms$').firstMatch(line)!.group(1)!;
}
