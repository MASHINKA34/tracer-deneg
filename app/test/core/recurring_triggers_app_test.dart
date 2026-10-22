import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/app.dart';
import 'package:milionchik/core/clock.dart';
import 'package:milionchik/core/data_startup.dart';
import 'package:milionchik/core/recurring_triggers.dart';
import 'package:milionchik/data/current_user.dart';
import 'package:milionchik/data/db/app_database.dart';
import 'package:milionchik/data/dev_seed.dart';
import 'package:milionchik/data/providers.dart';
import 'package:milionchik/data/repositories/budgets_repository.dart';
import 'package:milionchik/data/repositories/outbox_queue.dart';
import 'package:milionchik/data/repositories/prefs_repository.dart';
import 'package:milionchik/data/repositories/recurring_repository.dart';
import 'package:shared/shared.dart';

void main() {
  late List<LogRecord> records;
  late StreamSubscription<LogRecord> sub;

  setUpAll(() => initializeDateFormatting('ru'));

  setUp(() {
    records = [];
    Logger.root.level = Level.ALL;
    sub = Logger.root.onRecord.listen(records.add);
  });

  tearDown(() => sub.cancel());

  List<String> runLines() => [
    for (final r in records)
      if (r.loggerName == 'recurring' && r.level >= Level.INFO)
        formatLogRecord(r).split('\n').first,
  ];

  Future<String> seedRule(
    WidgetTester tester,
    AppDatabase db, {
    required int day,
    required YearMonth from,
  }) async => (await tester.runAsync(() async {
    final user = LocalPrefsCurrentUser(DriftPrefsRepository(db));
    final outbox = DriftOutboxQueue(db);
    final budget = await DriftBudgetsRepository(
      db,
      currentUser: user,
      outbox: outbox,
    ).createLocalPersonal();
    final categories = await (db.select(
      db.categories,
    )..where((c) => c.budgetId.equals(budget.id))).get();
    final rule =
        await DriftRecurringRepository(
          db,
          currentUser: user,
          outbox: outbox,
        ).create(
          budgetId: budget.id,
          categoryId: categories.firstWhere((c) => c.name == 'Связь').id,
          title: 'Интернет',
          amount: const Money.rubles(650),
          dayOfMonth: day,
          startMonth: from,
        );
    return rule.id;
  }))!;

  Future<List<LocalDate>> chargedOn(WidgetTester tester, AppDatabase db) async {
    final rows = await tester.runAsync(
      () =>
          (db.select(db.expenses)
                ..where((e) => e.recurringId.isNotNull())
                ..orderBy([(e) => OrderingTerm.asc(e.spentOn)]))
              .get(),
    );
    return [for (final row in rows!) row.spentOn];
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 10));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    }
  }

  void goBackground(WidgetTester tester) {
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
  }

  void comeBack(WidgetTester tester) {
    for (final state in [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
  }

  Future<void> unmount(WidgetTester tester, AppDatabase db) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
    await tester.runAsync(db.close);
  }

  group('RecurringTriggersScope с подменёнными часами', () {
    late DateTime now;

    Future<AppDatabase> mount(WidgetTester tester) async {
      final db = AppDatabase.memory();
      await seedRule(tester, db, day: 1, from: YearMonth(2026, 11));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            clockProvider.overrideWithValue(Clock(now: () => now)),
          ],
          child: const RecurringTriggersScope(child: SizedBox()),
        ),
      );
      await settle(tester);
      return db;
    }

    testWidgets('старт 31 октября: запуск «startup», трат нет', (tester) async {
      now = DateTime(2026, 10, 31, 22);
      final db = await mount(tester);

      expect(await chargedOn(tester, db), isEmpty);
      expect(runLines(), [
        matches(
          RegExp(
            r'INFO  \[recurring\] run \(startup\) today=2026-10-31 rules=1 '
            r'created=0 skipped=0 existing=0 deleted=0 in \d+ms$',
          ),
        ),
      ]);

      await unmount(tester, db);
    });

    testWidgets('фон → 1 ноября → возврат: запуск «day changed», трата 1-го', (
      tester,
    ) async {
      now = DateTime(2026, 10, 31, 22);
      final db = await mount(tester);

      goBackground(tester);
      now = DateTime(2026, 11, 1, 9, 15);
      comeBack(tester);
      await settle(tester);

      expect(await chargedOn(tester, db), [LocalDate(2026, 11, 1)]);
      expect(
        runLines().last,
        matches(
          RegExp(
            r'INFO  \[recurring\] run \(day changed\) today=2026-11-01 '
            r'rules=1 created=1 skipped=0 existing=0 deleted=0 in \d+ms$',
          ),
        ),
      );

      goBackground(tester);
      comeBack(tester);
      await settle(tester);
      expect(runLines(), hasLength(2));

      await unmount(tester, db);
    });

    testWidgets('полночь при открытом приложении: таймер → запуск '
        '«midnight», трата 1 ноября', (tester) async {
      now = DateTime(2026, 10, 31, 23, 59);
      final db = await mount(tester);
      expect(await chargedOn(tester, db), isEmpty);

      now = DateTime(2026, 11, 1, 0, 0, 1);
      await tester.pump(const Duration(seconds: 61));
      await settle(tester);

      expect(await chargedOn(tester, db), [LocalDate(2026, 11, 1)]);
      expect(runLines().last, contains('run (midnight) today=2026-11-01'));
      expect(runLines().last, contains('created=1'));

      await unmount(tester, db);
    });
  });

  testWidgets('appRoot: генератор работает с первого кадра, подмена «сегодня» '
      'на 1 ноября создаёт трату с причиной «day changed»', (tester) async {
    final db = AppDatabase.memory();
    await seedRule(tester, db, day: 1, from: YearMonth(2026, 11));

    await tester.pumpWidget(
      appRoot(
        DataReady(
          db,
          const DevSeedResult(DevSeedStatus.off),
          todayOverride: LocalDate(2026, 10, 22),
        ),
      ),
    );
    await settle(tester);

    expect(find.byType(RecurringTriggersScope), findsOneWidget);
    expect(runLines(), [contains('run (startup) today=2026-10-22 rules=1')]);
    expect(await chargedOn(tester, db), isEmpty);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(MilionchikApp)),
    );
    await tester.runAsync(
      () => container
          .read(todayOverrideProvider.notifier)
          .set(LocalDate(2026, 11, 1)),
    );
    await settle(tester);

    expect(await chargedOn(tester, db), [LocalDate(2026, 11, 1)]);
    expect(
      runLines().last,
      contains('run (day changed) today=2026-11-01 rules=1 created=1'),
    );

    await unmount(tester, db);
  });
}
