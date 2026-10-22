import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/app.dart';
import 'package:milionchik/core/clock.dart';
import 'package:milionchik/data/db/app_database.dart';
import 'package:milionchik/data/providers.dart';
import 'package:milionchik/data/queries/recurring_queries.dart';
import 'package:milionchik/features/recurring/recurring_screen.dart';
import 'package:milionchik/ui/components/bottom_nav.dart';
import 'package:milionchik/ui/components/expense_row.dart';
import 'package:shared/shared.dart';

import '../../support/app_scope.dart';
import '../../support/test_fonts.dart';
import '../shell/shell_harness.dart';
import 'recurring_fixture.dart';

const String _secret = 'Подписка для Ани';

final class _BrokenRecurringQueries implements RecurringQueries {
  final List<String> requested = [];

  @override
  Stream<Map<String, Expense>> watchMonthCharges(
    String budgetId,
    YearMonth month,
  ) {
    requested.add('$month');
    return Stream.error(
      SqliteException(
        extendedResultCode: 11,
        message: 'database disk image is malformed',
        causingStatement:
            'SELECT * FROM expenses INNER JOIN recurring_rules '
            'WHERE budget_id = ? AND comment = ?',
        parametersToStatement: [budgetId, _secret],
      ),
    );
  }
}

List<String> _recurring(Iterable<LogRecord> records, Level level) => [
  for (final r in records)
    if (r.loggerName == 'recurring' && r.level == level) r.message,
];

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testWidgets('открытие, удаление траты и «+» — debug [recurring]: бюджет, '
      'месяц, сколько правил, скоро и списано, мс; названий правил в логах '
      'нет', (tester) async {
    await loadTestFonts();
    final db = openTestDatabase();
    final budget = (await tester.runAsync(() => seedRecurringMockup(db)))!;
    final h = await ShellHarness.start(tester, db: db);
    await h.tapTab('Регулярные');
    final gym = budget.rules['Спортзал «Территория»']!;

    await writeWhileShown(
      tester,
      () => budget.expenses.delete(recurringExpenseId(gym.id, october)),
    );
    await tester.tap(find.bySemanticsLabel('Добавить регулярную трату'));
    await tester.pumpAndSettle();
    await h.systemBack();
    await tester.tap(find.text('Музыка'));
    await tester.pumpAndSettle();
    final music = budget.rules['Музыка']!;

    expect(
      _recurring(h.records, Level.FINE),
      containsAllInOrder([
        'recurring screen opened',
        matches(
          '^recurring screen built budgetId=${budget.id} month=2026-10 '
          'rules=5 upcoming=2 charged=3 monthlyKopecks=449800 in \\d+ms\$',
        ),
        'recurring screen updated budgetId=${budget.id} '
            'month=2026-10 → 2026-10 rules=5 → 5 upcoming=2 → 3 '
            'charged=3 → 2',
        'recurring add tap from=header → /recurring/new',
        'recurring editor opened new',
        'recurring rule tap section=upcoming #0 id=${music.id} day=24 '
            '→ /recurring/:id',
        'recurring editor opened id=${music.id}',
      ]),
    );
    expect(
      h.navDebug(),
      containsAllInOrder(['recurring editor closed new by back']),
    );
    expect(_recurring(h.records, Level.SEVERE), isEmpty);
    expect(_recurring(h.records, Level.WARNING), isEmpty);
    expect(_recurring(h.records, Level.INFO), isEmpty);
    for (final r in h.records) {
      if (r.loggerName != 'recurring' && r.loggerName != 'nav') continue;
      for (final title in mockupRules.map((m) => m.title)) {
        expect(r.message, isNot(contains(title)));
      }
      expect(r.message, isNot(contains('₽')));
    }
  });

  testWidgets('категории правила нет среди живых — один warn [recurring] с id '
      'категории и бюджетом, строка как «Другое»', (tester) async {
    await loadTestFonts();
    final db = openTestDatabase();
    final budget = (await tester.runAsync(() async {
      final b = await seedRecurringBudget(db);
      await b.rule('Облако', category: 'Кино', rubles: 149, day: 25);
      await (db.update(db.categories)
            ..where((c) => c.id.equals(b.categoryIds['Кино']!)))
          .write(CategoriesCompanion(deletedAt: Value(DateTime.utc(2026))));
      return b;
    }))!;
    final h = await ShellHarness.start(tester, db: db);
    await h.tapTab('Регулярные');
    await writeWhileShown(
      tester,
      () => budget.rule('Ещё', category: 'Связь', rubles: 100, day: 26),
    );

    expect(_recurring(h.records, Level.WARNING), [
      'recurring rule category=${budget.categoryIds['Кино']} of '
          'budgetId=${budget.id} not found among live categories, row shown '
          'as system «other»',
    ]);
    final row = tester.widgetList<ExpenseRow>(find.byType(ExpenseRow)).first;
    expect(row.title, 'Облако');
    expect(row.emoji, presetCategories.firstWhere((p) => p.isSystem).emoji);
  });

  testWidgets('траты правил не прочитались — error [recurring] с бюджетом и '
      'потоком, тип, код, SQL и стек, параметры только типами; на экране текст '
      'ошибки, «+» в шапке нет', (tester) async {
    await loadTestFonts();
    final records = <LogRecord>[];
    Logger.root.level = Level.ALL;
    final sub = Logger.root.onRecord.listen(records.add);
    addTearDown(sub.cancel);
    final db = openTestDatabase();
    final budget = (await tester.runAsync(() => seedRecurringMockup(db)))!;
    final broken = _BrokenRecurringQueries();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          clockProvider.overrideWithValue(Clock(now: () => testNow)),
          recurringQueriesProvider.overrideWithValue(broken),
        ],
        child: MilionchikApp(today: LocalDate(2026, 10, 19)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AppBottomNav),
        matching: find.text('Регулярные'),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(ExpenseRow), findsNothing);
    expect(
      find.text('Не удалось загрузить регулярные траты. Открой вкладку позже.'),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(RecurringScreen),
        matching: find.bySemanticsLabel('Добавить регулярную трату'),
      ),
      findsNothing,
    );
    final errors = [
      for (final r in records)
        if (r.loggerName == 'recurring' && r.level == Level.SEVERE)
          formatLogRecord(r),
    ];
    expect(errors, hasLength(1));
    final line = errors.single;
    expect(
      line,
      matches(
        'ERROR \\[recurring\\] recurring screen failed '
        'budgetId=${budget.id}: charges stream failed month=2026-10 '
        'after \\d+ms, showing error text: SqliteException',
      ),
    );
    expect(line, contains('database disk image is malformed'));
    expect(line, contains('WHERE budget_id = ? AND comment = ?'));
    expect(
      line,
      contains('<text:${budget.id.length}>, <text:${_secret.length}>'),
    );
    expect(line, contains('stack:'));
    expect(broken.requested, ['2026-10']);
    for (final r in records) {
      expect(formatLogRecord(r), isNot(contains(_secret)));
      expect('${r.error}', isNot(contains(_secret)));
    }
  });
}
