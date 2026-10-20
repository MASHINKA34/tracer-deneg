import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/core/logging/provider_logger.dart';
import 'package:milionchik/data/current_user.dart';
import 'package:milionchik/data/queries/month_queries.dart';
import 'package:milionchik/data/queries/search_queries.dart';
import 'package:milionchik/data/queries/stats_queries.dart';
import 'package:milionchik/data/providers.dart';
import 'package:milionchik/data/repositories/budgets_repository.dart';
import 'package:milionchik/data/repositories/categories_repository.dart';
import 'package:milionchik/data/repositories/expenses_repository.dart';
import 'package:milionchik/data/repositories/members_repository.dart';
import 'package:milionchik/data/repositories/outbox_queue.dart';
import 'package:milionchik/data/repositories/prefs_repository.dart';
import 'package:milionchik/data/repositories/recurring_repository.dart';
import 'package:shared/shared.dart';

import 'provider_harness.dart';

final class _FixedUser implements CurrentUser {
  const _FixedUser();

  @override
  Future<String> userId() async => 'user-fixed';
}

void main() {
  test('все провайдеры данных берут переопределённую in-memory базу: шесть '
      'репозиториев, очередь, CurrentUser и три набора запросов', () async {
    final h = ProviderHarness();

    expect(h.read(appDatabaseProvider), same(h.db));
    expect(h.read(prefsRepositoryProvider), isA<DriftPrefsRepository>());
    expect(h.read(currentUserProvider), isA<LocalPrefsCurrentUser>());
    expect(h.read(outboxQueueProvider), isA<DriftOutboxQueue>());
    expect(h.read(expensesRepositoryProvider), isA<DriftExpensesRepository>());
    expect(
      h.read(categoriesRepositoryProvider),
      isA<DriftCategoriesRepository>(),
    );
    expect(
      h.read(recurringRepositoryProvider),
      isA<DriftRecurringRepository>(),
    );
    expect(h.read(budgetsRepositoryProvider), isA<DriftBudgetsRepository>());
    expect(h.read(membersRepositoryProvider), isA<DriftMembersRepository>());
    expect(h.read(monthQueriesProvider), isA<DriftMonthQueries>());
    expect(h.read(statsQueriesProvider), isA<DriftStatsQueries>());
    expect(h.read(searchQueriesProvider), isA<DriftSearchQueries>());
    expect(
      h.read(expensesRepositoryProvider),
      same(h.read(expensesRepositoryProvider)),
    );

    final userId = await h.read(currentUserProvider).userId();
    final budget = await h
        .read(budgetsRepositoryProvider)
        .createLocalPersonal();

    expect(budget.ownerId, userId);
    expect(
      await h.read(prefsRepositoryProvider).getString(PrefKeys.localUserId),
      userId,
    );
    expect(await h.read(outboxQueueProvider).count(), 12);
  });

  test(
    'CurrentUser переопределяется в тестах и доходит до репозиториев',
    () async {
      final h = ProviderHarness(
        overrides: [currentUserProvider.overrideWithValue(const _FixedUser())],
      );

      final budget = await h
          .read(budgetsRepositoryProvider)
          .createLocalPersonal();

      expect(budget.ownerId, 'user-fixed');
      expect(budget.updatedBy, 'user-fixed');
    },
  );

  test('без базы при старте — понятная ошибка с именем провайдера и '
      'предупреждение [providers], а не тихий null', () {
    Logger.root.level = Level.ALL;
    final records = <LogRecord>[];
    final sub = Logger.root.onRecord.listen(records.add);
    addTearDown(sub.cancel);
    final container = ProviderContainer.test(
      observers: const [ProviderLogger()],
    );

    expect(
      () => container.read(expensesRepositoryProvider),
      throwsA(
        predicate(
          (Object e) => '$e'.contains(
            'appDatabaseProvider has no database: override it with the one '
            'opened at startup',
          ),
        ),
      ),
    );
    final warnings = [
      for (final r in records)
        if (r.loggerName == 'providers' && r.level == Level.WARNING) r.message,
    ];
    expect(
      warnings,
      contains(
        startsWith(
          'provider appDatabase failed, exposed as error state: '
          'UnimplementedError',
        ),
      ),
    );
  });

  test('выбранный бюджет: пустая база — null, после создания личного — его '
      'id, общий бюджет с сервера выбор не меняет', () async {
    final h = ProviderHarness();
    final selected = h.watch(selectedBudgetIdProvider);

    expect(await selected.data(), isNull);

    final personal = await h
        .read(budgetsRepositoryProvider)
        .createLocalPersonal();
    expect(await selected.data((id) => id != null), personal.id);

    await h.read(budgetsRepositoryProvider).applyFromServer([
      Budget(
        id: 'budget-shared',
        kind: BudgetKind.shared,
        name: 'Семья',
        emoji: '🏠',
        ownerId: 'user-other',
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
        updatedBy: 'user-other',
        seq: 5,
      ),
    ]);
    await pumpEventQueue();

    expect(selected.last.requireValue, personal.id);
    expect([
      for (final v in selected.values) v.value,
    ], containsAllInOrder([null, personal.id]));
    expect(h.lines('budgets'), [
      endsWith(
        'INFO  [budgets] selected budget: none, no personal budget in '
        'database yet',
      ),
      endsWith(
        'INFO  [budgets] selected budget budgetId=${personal.id} '
        'reason=personal',
      ),
    ]);
  });

  test('ошибка потока поиска — состояние ошибки сразу, без повторов, в логе '
      '[providers] имя провайдера и тип ошибки без текста запроса', () async {
    final h = ProviderHarness();
    final budget = await h
        .read(budgetsRepositoryProvider)
        .createLocalPersonal();
    await h.db.customStatement('DROP TABLE expenses');

    final search = h.watch(
      searchProvider(SearchFilters(budgetId: budget.id, text: 'Пятёрочка')),
    );
    final error = await search.error();
    await Future<void>.delayed(const Duration(milliseconds: 400));

    expect('$error', contains('no such table: expenses'));
    expect(search.last, isA<AsyncError<SearchResult>>());
    expect(search.last.retrying, isFalse);
    expect(search.values.whereType<AsyncError<SearchResult>>(), hasLength(1));

    final lines = h.lines('providers', Level.WARNING);
    expect(lines, hasLength(1));
    expect(
      lines.single,
      contains(
        'WARN  [providers] provider search(SearchFilters(budget=${budget.id} '
        'length=9 period=all categories=0)) failed, exposed as error state: '
        'SqliteException',
      ),
    );
    expect(lines.single, contains('no such table: expenses'));
    expect(lines.single, contains('stack:'));
    for (final line in [...lines, ...h.lines('query')]) {
      expect(line.toLowerCase(), isNot(contains('пятерочка')));
      expect(line.toLowerCase(), isNot(contains('пятёрочка')));
    }
  });

  test('провайдеры family живут, пока их слушают: [providers] debug — '
      'добавлен и удалён с аргументом', () async {
    final h = ProviderHarness();
    final key = (budgetId: 'budget-x', month: YearMonth(2026, 10));
    final total = h.watch(monthTotalProvider(key));

    expect(await total.data(), Money.zero);
    expect(
      monthTotalProvider(key),
      monthTotalProvider((budgetId: 'budget-x', month: YearMonth(2026, 10))),
    );
    total.close();
    await pumpEventQueue();

    final debug = [
      for (final r in h.records)
        if (r.loggerName == 'providers' && r.level == Level.FINE) r.message,
    ];
    expect(
      debug,
      containsAllInOrder([
        'provider added monthTotal((budgetId: budget-x, month: 2026-10))',
        'provider disposed monthTotal((budgetId: budget-x, month: 2026-10))',
      ]),
    );
  });
}
