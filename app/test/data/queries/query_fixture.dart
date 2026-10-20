import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/data/db/app_database.dart';
import 'package:milionchik/data/queries/month_queries.dart';
import 'package:milionchik/data/queries/query_runner.dart';
import 'package:milionchik/data/queries/search_queries.dart';
import 'package:milionchik/data/queries/stats_queries.dart';
import 'package:milionchik/ui/catalog/demo_months.dart';
import 'package:shared/shared.dart';

import '../repositories/repository_harness.dart';

export '../repositories/repository_harness.dart';

final class Spend {
  const Spend(this.day, this.category, this.amount, this.comment, this.time);

  final int day;
  final String category;
  final Money amount;
  final String comment;
  final String time;
}

final YearMonth october = demoAutumn.month;
final LocalDate today = demoAutumn.today;

const List<Spend> octoberSpends = [
  Spend(1, 'Кафе', Money.rubles(450), 'Кофе с собой', '08:30'),
  Spend(2, 'Продукты', Money.rubles(1130, 10), 'Пятёрочка', '19:00'),
  Spend(2, 'Связь', Money.rubles(149, 90), 'тариф_мини', '10:00'),
  Spend(3, 'Кафе', Money.rubles(170), 'Кофе с собой', '08:10'),
  Spend(3, 'Продукты', Money.rubles(2170), 'Ашан', '12:00'),
  Spend(5, 'Транспорт', Money.rubles(860), 'Такси', '23:10'),
  Spend(6, 'Кафе', Money.rubles(320), 'КОФЕ И ПИРОГ', '09:00'),
  Spend(7, 'Транспорт', Money.rubles(450), 'Метро', '08:00'),
  Spend(8, 'Дом', Money.rubles(1150), 'Ёлка искусственная', '15:00'),
  Spend(9, 'Продукты', Money.rubles(540), 'ВкусВилл', '18:00'),
  Spend(10, 'Одежда', Money.rubles(1640), 'Куртка', '14:00'),
  Spend(10, 'Продукты', Money.rubles(1030), 'Пятёрочка', '19:30'),
  Spend(11, 'Кафе', Money.rubles(190), 'Кофе с собой', '08:20'),
  Spend(11, 'Продукты', Money.rubles(800), 'Пятёрочка', '20:00'),
  Spend(12, 'Здоровье', Money.rubles(2900), 'Аптека', '11:00'),
  Spend(13, 'Дом', Money.rubles(210), 'Маленькая елка', '17:00'),
  Spend(15, 'Кафе', Money.rubles(340), 'Кофе и круассан', '08:40'),
  Spend(15, 'Продукты', Money.rubles(420), 'кофе в зёрнах', '17:00'),
  Spend(16, 'Транспорт', Money.rubles(430), 'Метро', '09:00'),
  Spend(17, 'Кафе', Money.rubles(890), 'Обед с коллегами', '13:30'),
  Spend(17, 'Продукты', Money.rubles(560), 'ВкусВилл', '19:10'),
  Spend(18, 'Развлечения', Money.rubles(400), 'Кино 50% скидка', '20:00'),
  Spend(19, 'Кафе', Money.rubles(210), 'Кофе с собой', '09:15'),
  Spend(19, 'Продукты', Money.rubles(640), 'Пятёрочка', '18:40'),
  Spend(19, 'Транспорт', Money.rubles(250), '', '20:00'),
];

const List<Spend> septemberSpends = [
  Spend(20, 'Дом', Money.rubles(6400), 'Ремонт ноутбука', '12:00'),
  Spend(21, 'Продукты', Money.rubles(64), 'Хлеб', '09:00'),
];

const String deletedComment = 'Кофе удалённый ёлка';

DateTime moscowTime(LocalDate day, String time) {
  final parts = time.split(':');
  return DateTime.utc(
    day.year,
    day.month,
    day.day,
    int.parse(parts[0]) - 3,
    int.parse(parts[1]),
  );
}

List<Spend> demoSpends(DemoMonth month) => [
  for (final e in month.rubles.entries)
    Spend(e.key, 'Продукты', Money.rubles(e.value), '', '12:00'),
];

final class QueryHarness {
  QueryHarness({AppDatabase? db, this.slowThreshold = slowQueryThreshold})
    : repo = RepositoryHarness(db: db) {
    final level = _printLevel;
    if (level != null) {
      _print = Logger.root.onRecord
          .where((r) => r.loggerName == 'query' && r.level >= level)
          .listen((r) => debugPrint(formatLogRecord(r)));
    }
  }

  static final Level? _printLevel = parseLogLevel(
    const String.fromEnvironment('LOG_LEVEL'),
  );

  final RepositoryHarness repo;
  final Duration slowThreshold;
  StreamSubscription<LogRecord>? _print;

  AppDatabase get db => repo.db;

  late final DriftMonthQueries month = DriftMonthQueries(
    db,
    slowThreshold: slowThreshold,
  );

  late final DriftStatsQueries stats = DriftStatsQueries(
    db,
    slowThreshold: slowThreshold,
  );

  late final DriftSearchQueries search = DriftSearchQueries(
    db,
    slowThreshold: slowThreshold,
  );

  late SeededBudget budget;
  late SeededBudget otherBudget;
  final List<Expense> live = [];

  int _ids = 0;

  Future<void> seedMockup() async {
    budget = await repo.seedBudget(id: 'budget-main');
    otherBudget = await repo.seedBudget(id: 'budget-other');
    await seed(budget, october, octoberSpends);
    await seed(budget, YearMonth(2026, 9), septemberSpends);
    for (final demo in [demoWinter, demoSpring, demoSummer]) {
      await seed(budget, demo.month, demoSpends(demo));
    }
    await seed(budget, YearMonth(2025, 12), const [
      Spend(31, 'Продукты', Money.rubles(5000), 'Новогодний стол', '18:00'),
    ]);
    await seed(otherBudget, october, const [
      Spend(19, 'Кафе', Money.rubles(640), 'Кофе из другого бюджета', '22:00'),
    ]);
    await seedDeleted(budget, october.dayOf(4));
  }

  Future<List<Expense>> seed(
    SeededBudget b,
    YearMonth month,
    List<Spend> spends,
  ) async {
    final expenses = [for (final s in spends) _expense(b, month, s)];
    await repo.expenses.applyFromServer(expenses);
    if (b.id == budget.id) live.addAll(expenses);
    return expenses;
  }

  Future<Expense> seedDeleted(SeededBudget b, LocalDate day) async {
    final at = moscowTime(today, '23:00');
    final tombstone = _expense(
      b,
      day.yearMonth,
      Spend(day.day, 'Кафе', const Money.rubles(640), deletedComment, '23:00'),
      createdAt: at,
      deletedAt: at,
    );
    await repo.expenses.applyFromServer([tombstone]);
    return tombstone;
  }

  Expense _expense(
    SeededBudget b,
    YearMonth month,
    Spend s, {
    DateTime? createdAt,
    DateTime? deletedAt,
  }) {
    final day = month.dayOf(s.day);
    final at = createdAt ?? moscowTime(day, s.time);
    return Expense(
      id: '${b.id}-e${(++_ids).toString().padLeft(4, '0')}',
      budgetId: b.id,
      categoryId: b.byName(s.category).id,
      amount: s.amount,
      spentOn: day,
      comment: s.comment,
      authorId: meId,
      createdAt: at,
      updatedAt: at,
      updatedBy: meId,
      deletedAt: deletedAt,
      seq: _ids,
    );
  }

  Map<String, String> categoryNames(SeededBudget b) => {
    for (final c in b.categories) c.id: c.name,
  };

  String categoryOf(Expense e) => categoryNames(budget)[e.categoryId]!;

  List<LogRecord> queryLogs([Level? level]) => [
    for (final r in repo.records)
      if (r.loggerName == 'query' && (level == null || r.level == level)) r,
  ];

  Future<void> dispose() async {
    await _print?.cancel();
    await repo.dispose();
  }
}

final class Watcher<T> {
  Watcher(Stream<T> stream) : _it = StreamIterator(stream);

  final StreamIterator<T> _it;

  Future<T> next() async {
    if (!await _it.moveNext().timeout(const Duration(seconds: 5))) {
      throw StateError('stream closed');
    }
    return _it.current;
  }

  Future<void> cancel() => _it.cancel();
}

String describeSpends(Iterable<Expense> expenses, Map<String, String> names) =>
    [
      for (final e in expenses)
        '${e.spentOn.day}:${names[e.categoryId]}:${e.amount.format()}',
    ].join(', ');
