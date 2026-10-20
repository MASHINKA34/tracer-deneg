import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/data/db/app_database.dart';
import 'package:milionchik/data/queries/search_queries.dart';
import 'package:shared/shared.dart';

import 'query_fixture.dart';

const List<String> _secrets = [
  'секрет',
  'кофе',
  'Пятёрочка',
  '64000',
  '18300',
  '1830000',
];

List<String> _messages(QueryHarness h, Level level) => [
  for (final r in h.queryLogs(level)) r.message,
];

void _expectNoSecrets(String line) {
  for (final secret in _secrets) {
    expect(
      line.toLowerCase(),
      isNot(contains(secret.toLowerCase())),
      reason: secret,
    );
  }
}

String _severeLine(QueryHarness h) {
  final errors = h.queryLogs(Level.SEVERE);
  expect(errors, hasLength(1));
  return formatLogRecord(errors.single);
}

void main() {
  group('успех', () {
    late QueryHarness h;

    setUp(() async {
      h = QueryHarness();
      await h.seedMockup();
    });

    tearDown(() => h.dispose());

    test('каждый запрос - debug: имя, бюджет, период, строки, мс', () async {
      final id = h.budget.id;
      await h.month.watchDayTotals(id, october).first;
      await h.month.watchMonthTotal(id, october).first;
      await h.month.watchDayExpenses(id, october.dayOf(17)).first;
      await h.stats
          .watchCategoryTotals(id, from: october.firstDay, to: october.lastDay)
          .first;
      await h.stats.watchMonthTotals(id, 2026).first;
      await h.search.watchRecentComments(id).first;

      final debug = _messages(h, Level.FINE);
      const month = 'period=2026-10-01..2026-10-31';
      expect(debug, [
        matches(
          '^query day-totals budget=$id $month rows=17 '
          r'trigger=listen in \d+ms$',
        ),
        matches(
          '^query month-total budget=$id $month rows=1 '
          r'trigger=listen in \d+ms$',
        ),
        matches(
          '^query day-expenses budget=$id '
          'period=2026-10-17..2026-10-17 rows=2 '
          r'trigger=listen in \d+ms$',
        ),
        matches(
          '^query category-totals budget=$id $month rows=8 '
          r'trigger=listen in \d+ms$',
        ),
        matches(
          '^query month-totals budget=$id '
          'period=2026-01-01..2026-12-31 rows=5 '
          r'trigger=listen in \d+ms$',
        ),
        matches(
          '^query recent-comments budget=$id limit=6 rows=6 '
          r'trigger=listen in \d+ms$',
        ),
      ]);
      expect(h.queryLogs().where((r) => r.level >= Level.INFO), isEmpty);
    });

    test(
      'поиск - длина запроса и фильтры вместо текста, число найденных',
      () async {
        await h.search
            .watchSearch(SearchFilters(budgetId: h.budget.id, text: ' Кофе '))
            .first;
        await h.search
            .watchSearch(
              SearchFilters(
                budgetId: h.budget.id,
                text: '640',
                from: october.firstDay,
                categoryIds: {
                  h.budget.byName('Продукты').id,
                  h.budget.byName('Кафе').id,
                },
              ),
            )
            .first;

        final debug = _messages(h, Level.FINE);
        expect(debug, [
          matches(
            '^query search budget=${h.budget.id} period=all categories=0 '
            r'length=4 amount=false rows=7 trigger=listen in \d+ms$',
          ),
          matches(
            '^query search budget=${h.budget.id} period=2026-10-01.. '
            'categories=2 length=3 amount=true rows=1 '
            r'trigger=listen in \d+ms$',
          ),
        ]);
        for (final r in h.queryLogs()) {
          _expectNoSecrets(formatLogRecord(r));
        }
      },
    );

    test('повторный запуск по изменению таблиц - trigger=change', () async {
      final days = Watcher(h.month.watchDayTotals(h.budget.id, october));
      addTearDown(days.cancel);
      await days.next();

      await h.repo.expenses.create(
        budgetId: h.budget.id,
        categoryId: h.budget.byName('Кафе').id,
        amount: const Money.rubles(500),
        spentOn: october.dayOf(20),
      );
      await days.next();

      expect(_messages(h, Level.FINE), [
        contains('rows=17 trigger=listen'),
        contains('rows=18 trigger=change'),
      ]);
    });
  });

  test('медленный запрос - warn с именем и параметрами', () async {
    final h = QueryHarness(slowThreshold: Duration.zero);
    addTearDown(h.dispose);
    await h.seedMockup();

    await h.month.watchMonthTotal(h.budget.id, october).first;
    await h.search
        .watchSearch(SearchFilters(budgetId: h.budget.id, text: 'секрет'))
        .first;

    expect(_messages(h, Level.FINE), isEmpty);
    expect(_messages(h, Level.WARNING), [
      matches(
        '^query month-total slow budget=budget-main '
        'period=2026-10-01..2026-10-31 rows=1 trigger=listen '
        r'in \d+ms threshold=0ms$',
      ),
      matches(
        '^query search slow budget=budget-main period=all categories=0 '
        'length=6 amount=false rows=0 trigger=listen '
        r'in \d+ms threshold=0ms$',
      ),
    ]);
  });

  Future<void> expectFailure(QueryHarness h) async {
    await h.seedMockup();
    await h.seed(h.budget, october, const [
      Spend(4, 'Кафе', Money(1 << 62), 'Секретный кофе', '10:00'),
      Spend(4, 'Кафе', Money(1 << 62), 'Секретный кофе', '11:00'),
    ]);

    await expectLater(
      h.search
          .watchSearch(
            SearchFilters(
              budgetId: h.budget.id,
              text: 'Секретный кофе',
              from: october.firstDay,
              to: october.lastDay,
            ),
          )
          .first,
      throwsA(anything),
    );

    final line = _severeLine(h);
    expect(
      line,
      contains(
        'ERROR [query] query search failed budget=budget-main '
        'period=2026-10-01..2026-10-31 categories=0 length=14 amount=false '
        'trigger=listen after ',
      ),
    );
    expect(line, contains('SqliteException(1)'));
    expect(line, contains('integer overflow'));
    expect(line, contains('Causing statement: SELECT COUNT(*)'));
    expect(
      line,
      contains(
        'parameters: <text:11>, <text:10>, <text:10>, <text:16>, <text:16>',
      ),
    );
    _expectNoSecrets(line);
    expect(line, isNot(contains('${1 << 62}')));
    final stack = line.indexOf('\n  stack:\n');
    expect(stack, greaterThan(0));
    expect(
      line.substring(stack),
      contains('package:milionchik/data/queries/query_runner.dart'),
    );
  }

  test('ошибка - error с именем, параметрами, sql и стеком, без текста '
      'запроса и значений параметров', () async {
    final h = QueryHarness();
    addTearDown(h.dispose);

    await expectFailure(h);
  });

  test('ошибка в фоновом изоляте, как в приложении - так же без текста '
      'запроса', () async {
    final dir = await Directory.systemTemp.createTemp('milionchik_query_');
    final h = QueryHarness(
      db: AppDatabase(
        NativeDatabase.createInBackground(File('${dir.path}/test.sqlite')),
      ),
    );
    addTearDown(() async {
      await h.dispose();
      await dir.delete(recursive: true);
    });

    await expectFailure(h);
  });

  test('ошибка в месячном запросе - тоже error, поток отдаёт ошибку', () async {
    final h = QueryHarness();
    addTearDown(h.dispose);
    await h.seedMockup();
    await h.db.customStatement('DROP TABLE expenses');

    await expectLater(
      h.month.watchDayTotals(h.budget.id, october).first,
      throwsA(anything),
    );

    final line = _severeLine(h);
    expect(
      line,
      contains(
        'ERROR [query] query day-totals failed budget=budget-main '
        'period=2026-10-01..2026-10-31 trigger=listen after ',
      ),
    );
    expect(line, contains('no such table: expenses'));
    expect(line, isNot(contains("'budget-main'")));
  });
}
