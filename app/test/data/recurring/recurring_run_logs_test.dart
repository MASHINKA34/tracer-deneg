import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/data/recurring_service.dart';
import 'package:milionchik/data/repositories/expenses_repository.dart';
import 'package:milionchik/data/repositories/recurring_repository.dart';
import 'package:shared/shared.dart';

import 'recurring_harness.dart';

final class _BlindExpenses implements ExpensesRepository {
  _BlindExpenses(this._inner);

  final ExpensesRepository _inner;

  @override
  Future<({Set<String> live, Set<String> deleted})> existingByIds(
    Iterable<String> ids,
  ) async => (live: <String>{}, deleted: <String>{});

  @override
  Future<Expense> createRecurring(
    RecurringRule rule,
    PlannedRecurringExpense planned,
  ) => _inner.createRecurring(rule, planned);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _BrokenRules implements RecurringRepository {
  @override
  Future<List<RecurringRule>> liveRulesOfLiveBudgets() async =>
      throw StateError('disk I/O error');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late RecurringHarness r;

  setUp(() async => r = await RecurringHarness().seed());

  tearDown(() => r.dispose());

  String firstLine(LogRecord record) =>
      formatLogRecord(record).split('\n').first;

  List<String> recurringFirstLines([Level level = Level.INFO]) => [
    for (final record in r.logs('recurring', level)) firstLine(record),
  ];

  List<String> everything() => [
    for (final record in r.repo.records) ...[
      formatLogRecord(record),
      if (record.error != null) '${record.error}',
    ],
  ];

  Future<RecurringRule> fromServer({
    required String id,
    int day = 5,
    Money amount = const Money.rubles(650),
  }) async {
    final at = DateTime.utc(2026, 10, 1, 7);
    final rule = RecurringRule(
      id: id,
      budgetId: r.budget.id,
      categoryId: r.budget.byName('Связь').id,
      title: internetTitle,
      amount: amount,
      dayOfMonth: day,
      startMonth: YearMonth(2026, 10),
      createdAt: at,
      updatedAt: at,
      updatedBy: serverUserId,
      seq: 3,
    );
    await r.repo.recurring.applyFromServer([rule]);
    return rule;
  }

  test('успешный запуск: одна строка info — причина, правила, создано, '
      'пропущено, мс; название и суммы не выше debug', () async {
    final rule = await r.rule(day: 5, from: YearMonth(2026, 9));
    await r.run();
    await r.repo.expenses.delete(
      recurringExpenseId(rule.id, YearMonth(2026, 9)),
    );
    r.repo.records.clear();
    r.today = LocalDate(2026, 11, 5);

    await r.run(RecurringRunReason.dayChanged);

    expect(recurringFirstLines(), [
      matches(
        RegExp(
          r'INFO  \[recurring\] run \(day changed\) today=2026-11-05 rules=1 '
          r'created=1 skipped=2 existing=1 deleted=1 in \d+ms$',
        ),
      ),
    ]);
    final infoAndAbove = [
      for (final record in r.repo.records)
        if (record.level >= Level.INFO) formatLogRecord(record),
    ];
    expect(infoAndAbove.join('\n'), isNot(contains(internetTitle)));
    expect(infoAndAbove.join('\n'), isNot(contains('65000')));
    expect(
      recurringFirstLines(Level.ALL),
      contains(
        contains(
          'rule ${rule.id} budget=${r.budget.id} day=5 from=2026-09 due=3 '
          'created=2026-11 existing=1 deleted=1',
        ),
      ),
    );
  });

  test('сумма правила вне допустимой — error с id правила и месяцем, '
      'остальные правила создаются, итог warn', () async {
    final broken = await fromServer(id: 'rule-zero', amount: const Money(0));
    final fine = await r.rule(day: 5, from: YearMonth(2026, 10));

    final result = await r.run();

    expect(result.created, 1);
    expect(result.failedRules, 1);
    expect(result.ok, isFalse);
    expect(await r.expensesOf(broken.id), isEmpty);
    expect(await r.expensesOf(fine.id), hasLength(1));
    final brokenId = recurringExpenseId(broken.id, YearMonth(2026, 10));
    expect(recurringFirstLines(Level.WARNING), [
      endsWith(
        'ERROR [recurring] run (startup) rule rule-zero month=2026-10 '
        'expense $brokenId not created, its changes rolled back, later '
        'months of this rule wait for the next run: RepositoryException: '
        'RepositoryException(validation entity=expense id=$brokenId '
        'validation=amount_empty)',
      ),
      matches(
        RegExp(
          r'WARN  \[recurring\] run \(startup\) today=2026-10-22 rules=2 '
          r'created=1 skipped=0 existing=0 deleted=0 failedRules=1 in \d+ms: '
          r'errors above, failed rules retry on the next run$',
        ),
      ),
    ]);
  });

  test('день списания вне 1–31 — error с id правила и месяцами, другое '
      'правило создаётся', () async {
    await fromServer(id: 'rule-day-0', day: 0);
    final fine = await r.rule(day: 5, from: YearMonth(2026, 10));

    final result = await r.run();

    expect(result.created, 1);
    expect(result.failedRules, 1);
    expect(await r.expensesOf(fine.id), hasLength(1));
    expect(
      recurringFirstLines(Level.SEVERE).single,
      endsWith(
        'ERROR [recurring] run (startup) rule rule-day-0 skipped: charge '
        'months not computed budget=${r.budget.id} day=0 '
        'month=2026-10..2026-10 today=2026-10-22: RangeError: RangeError '
        '(dayOfMonth): '
        'Invalid value: Not in inclusive range 1..31: 0',
      ),
    );
  });

  test('гонка с другим процессом: id уже занят — error с правилом и месяцем, '
      'параметры запроса (название) в лог не попадают', () async {
    final rule = await r.rule(day: 5, from: YearMonth(2026, 10));
    await r.run();
    r.repo.records.clear();

    final blind = RecurringService(
      r.repo.db,
      expenses: _BlindExpenses(r.repo.expenses),
      recurring: r.repo.recurring,
      clock: r.clock,
    );
    final result = await blind.run(RecurringRunReason.background);

    expect(result.created, 0);
    expect(result.failedRules, 1);
    expect(await r.expensesOf(rule.id), hasLength(1));
    final id = recurringExpenseId(rule.id, YearMonth(2026, 10));
    expect(
      recurringFirstLines(Level.SEVERE).single,
      contains(
        'ERROR [recurring] run (background) rule ${rule.id} month=2026-10 '
        'expense $id not created, its changes rolled back',
      ),
    );
    expect(recurringFirstLines(Level.SEVERE).single, contains('UNIQUE'));
    final all = everything().join('\n');
    expect(all, isNot(contains(internetTitle)));
    expect(all, isNot(contains(normalizeSearchText(internetTitle))));
    expect(all, isNot(contains('65000')));
  });

  test('сбой чтения правил — error с шагом, транзакция откатана, ничего не '
      'создано', () async {
    final service = RecurringService(
      r.repo.db,
      expenses: r.repo.expenses,
      recurring: _BrokenRules(),
      clock: r.clock,
    );

    final result = await service.run(RecurringRunReason.midnight);

    expect(result.ok, isFalse);
    expect(result.error, isA<StateError>());
    expect(result.created, 0);
    expect(await r.expenseCount(), 0);
    expect(recurringFirstLines(Level.WARNING), [
      matches(
        RegExp(
          r'ERROR \[recurring\] run \(midnight\) failed today=2026-10-22 '
          r'step=reading rules after \d+ms, transaction rolled back, '
          r'nothing created: StateError: Bad state: disk I/O error$',
        ),
      ),
    ]);
  });
}
