import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import 'current_user.dart';
import 'db/app_database.dart';
import 'db/redact_db_error.dart';
import 'repositories/budgets_repository.dart';
import 'repositories/categories_repository.dart';
import 'repositories/expenses_repository.dart';
import 'repositories/outbox_queue.dart';

const String devSeedDefine = String.fromEnvironment('DEV_SEED');

final _log = Logger('seed');

enum DevSeedStatus { off, ignored, skipped, seeded, failed }

final class DevSeedResult {
  const DevSeedResult(
    this.status, {
    this.budgets = 0,
    this.categories = 0,
    this.expenses = 0,
    this.elapsed = Duration.zero,
  });

  final DevSeedStatus status;
  final int budgets;
  final int categories;
  final int expenses;
  final Duration elapsed;

  @override
  String toString() =>
      'DevSeedResult(${status.name} budgets=$budgets '
      'categories=$categories expenses=$expenses '
      'in ${elapsed.inMilliseconds}ms)';
}

final class DevSeed {
  DevSeed(this._db, {required this._currentUser});

  final AppDatabase _db;
  final CurrentUser _currentUser;

  DateTime _at = DateTime.now();

  late final DriftOutboxQueue _queue = DriftOutboxQueue(_db, now: _now);

  late final _CountingOutbox _outbox = _CountingOutbox(_queue);

  late final DriftBudgetsRepository _budgets = DriftBudgetsRepository(
    _db,
    currentUser: _currentUser,
    outbox: _outbox,
    now: _now,
  );

  late final DriftCategoriesRepository _categories = DriftCategoriesRepository(
    _db,
    currentUser: _currentUser,
    outbox: _outbox,
    now: _now,
  );

  late final DriftExpensesRepository _expenses = DriftExpensesRepository(
    _db,
    currentUser: _currentUser,
    outbox: _outbox,
    now: _now,
  );

  DateTime _now() => _at;

  Future<DevSeedResult> runIfRequested({
    String flag = devSeedDefine,
    bool debugBuild = kDebugMode,
  }) async {
    if (flag.isEmpty) return const DevSeedResult(DevSeedStatus.off);
    if (!debugBuild) {
      _log.warning('DEV_SEED=$flag ignored: works only in debug builds');
      return const DevSeedResult(DevSeedStatus.ignored);
    }
    if (flag != 'true') {
      _log.warning(
        'DEV_SEED=$flag ignored: only DEV_SEED=true turns the dev seed on',
      );
      return const DevSeedResult(DevSeedStatus.ignored);
    }
    _log.info(
      'dev seed requested DEV_SEED=true build=debug '
      'months=${_seedMonths.first.month}..${_seedMonths.last.month}',
    );
    return _seed();
  }

  Future<DevSeedResult> _seed() async {
    final sw = Stopwatch()..start();
    var step = 'current-user';
    var created = 0;
    String? budgetId;
    _outbox.enqueued = 0;
    try {
      final userId = await _currentUser.userId();
      step = 'check-empty';
      final result = await _db.transaction(() async {
        final existing = await _existingRows();
        if (existing.values.any((n) => n > 0)) {
          final counts = existing.entries
              .map((e) => '${e.key}=${e.value}')
              .join(' ');
          _log.info(
            'dev seed skipped: database not empty $counts '
            'in ${sw.elapsedMilliseconds}ms',
          );
          return DevSeedResult(DevSeedStatus.skipped, elapsed: sw.elapsed);
        }
        _log.fine('dev seed: database empty, seeding userId=$userId');

        step = 'personal-budget';
        _at = _budgetCreatedAt;
        final budget = await _budgets.createLocalPersonal();
        budgetId = budget.id;
        step = 'categories';
        final categories = await _categories.watchByBudget(budget.id).first;
        final ids = {for (final c in categories) c.name: c.id};

        for (final month in _seedMonths) {
          step = 'expenses month=${month.month}';
          final monthWatch = Stopwatch()..start();
          var total = Money.zero;
          for (final spend in month.spends) {
            final categoryId =
                ids[spend.category] ??
                (throw StateError(
                  'dev seed category missing: preset name not found among '
                  '${ids.length} categories of budget=${budget.id}',
                ));
            _at = spend.createdAt(month.month);
            await _expenses.create(
              budgetId: budget.id,
              categoryId: categoryId,
              amount: spend.amount,
              spentOn: month.month.dayOf(spend.day),
              comment: spend.comment,
            );
            total += spend.amount;
            created++;
          }
          _log.fine(
            'dev seed month=${month.month} expenses=${month.spends.length} '
            'totalKopecks=${total.kopecks} '
            'in ${monthWatch.elapsedMilliseconds}ms',
          );
        }
        step = 'commit';
        return DevSeedResult(
          DevSeedStatus.seeded,
          budgets: 1,
          categories: categories.length,
          expenses: created,
        );
      });
      if (result.status != DevSeedStatus.seeded) return result;
      _log.info(
        'dev seed done budgets=${result.budgets} '
        'categories=${result.categories} expenses=${result.expenses} '
        'months=${_seedMonths.length} outbox=${_outbox.enqueued} '
        'budget=$budgetId in ${sw.elapsedMilliseconds}ms',
      );
      await _queue.reportSize('dev-seed');
      return DevSeedResult(
        DevSeedStatus.seeded,
        budgets: result.budgets,
        categories: result.categories,
        expenses: result.expenses,
        elapsed: sw.elapsed,
      );
    } catch (e, st) {
      final error = redactDbError(e);
      _log.severe(
        'dev seed failed step=$step created=$created '
        'after ${sw.elapsedMilliseconds}ms, seed rolled back, '
        'nothing seeded: ${describeError(error)}',
        error,
        st,
      );
      return DevSeedResult(DevSeedStatus.failed, elapsed: sw.elapsed);
    }
  }

  Future<Map<String, int>> _existingRows() async => {
    'budgets': await _db.budgets.count().getSingle(),
    'categories': await _db.categories.count().getSingle(),
    'expenses': await _db.expenses.count().getSingle(),
    'recurring': await _db.recurringRules.count().getSingle(),
  };
}

final class _CountingOutbox implements OutboxQueue {
  _CountingOutbox(this._inner);

  final OutboxQueue _inner;
  int enqueued = 0;

  @override
  Future<int> enqueueUpsert(SyncRecord record) {
    enqueued++;
    return _inner.enqueueUpsert(record);
  }

  @override
  Future<int> enqueueDelete(
    SyncEntity entity,
    String entityId, {
    required DateTime at,
    DateTime? notBefore,
  }) {
    enqueued++;
    return _inner.enqueueDelete(entity, entityId, at: at, notBefore: notBefore);
  }

  @override
  Future<bool> cancelPendingDelete(
    SyncEntity entity,
    String entityId, {
    required DateTime now,
  }) => _inner.cancelPendingDelete(entity, entityId, now: now);

  @override
  Future<List<PendingChange>> pending({int limit = maxPushBatchSize}) =>
      _inner.pending(limit: limit);

  @override
  Future<int> remove(Iterable<int> outboxIds) => _inner.remove(outboxIds);

  @override
  Future<int> count() => _inner.count();

  @override
  Stream<int> watchCount() => _inner.watchCount();

  @override
  Future<void> reportSize(String reason) async {}
}

final class _Spend {
  const _Spend(
    this.day,
    this.time,
    this.category,
    this.rubles,
    this.comment, {
    this.kopecks = 0,
  });

  final int day;
  final String time;
  final String category;
  final int rubles;
  final int kopecks;
  final String comment;

  Money get amount => Money.rubles(rubles, kopecks);

  DateTime createdAt(YearMonth month) {
    final [hour, minute] = time.split(':').map(int.parse).toList();
    return DateTime(month.year, month.month, day, hour, minute);
  }
}

final class _SeedMonth {
  _SeedMonth(this.month, this.spends);

  final YearMonth month;
  final List<_Spend> spends;
}

final DateTime _budgetCreatedAt = DateTime(2026, 8, 1, 8);

const String _food = 'Продукты';
const String _cafe = 'Кафе';
const String _transport = 'Транспорт';
const String _home = 'Дом';
const String _health = 'Здоровье';
const String _sport = 'Спорт';
const String _fun = 'Развлечения';
const String _clothes = 'Одежда';
const String _phone = 'Связь';
const String _gifts = 'Подарки';
const String _other = 'Другое';

final List<_SeedMonth> _seedMonths = [
  _SeedMonth(YearMonth(2026, 8), const [
    _Spend(1, '10:30', _cafe, 350, 'Кофе и круассан'),
    _Spend(1, '12:00', _food, 1460, 'Ашан'),
    _Spend(2, '10:00', _phone, 600, 'Мобильная связь'),
    _Spend(2, '19:00', _fun, 600, 'Кино'),
    _Spend(3, '08:10', _transport, 450, 'Пополнение Тройки'),
    _Spend(3, '08:30', _cafe, 190, 'Кофе с собой'),
    _Spend(4, '19:20', _food, 520, 'Пятёрочка'),
    _Spend(5, '13:20', _cafe, 640, 'Обед с коллегами'),
    _Spend(6, '18:00', _health, 760, 'Аптека'),
    _Spend(7, '19:00', _food, 430, 'ВкусВилл'),
    _Spend(7, '21:00', _cafe, 850, 'Ужин с друзьями'),
    _Spend(8, '17:30', _food, 680, 'Пятёрочка'),
    _Spend(10, '08:20', _cafe, 190, 'Кофе с собой'),
    _Spend(10, '09:00', _phone, 500, 'Домашний интернет'),
    _Spend(11, '23:00', _transport, 380, 'Такси'),
    _Spend(12, '11:00', _sport, 2900, 'Абонемент в зал'),
    _Spend(13, '20:00', _food, 610, 'Пятёрочка'),
    _Spend(14, '08:30', _cafe, 240, 'Кофе с собой'),
    _Spend(15, '12:30', _food, 1270, 'Ашан'),
    _Spend(15, '18:00', _fun, 900, 'Квест с друзьями'),
    _Spend(17, '08:30', _cafe, 190, 'Кофе с собой'),
    _Spend(17, '19:40', _food, 349, 'Молоко и хлеб', kopecks: 90),
    _Spend(19, '19:00', _transport, 120, 'Метро, 2 поездки'),
    _Spend(21, '21:00', _cafe, 620, 'Пицца с друзьями'),
    _Spend(22, '12:00', _other, 6400, 'Ремонт ноутбука'),
    _Spend(22, '15:00', _food, 820, 'Ашан'),
    _Spend(24, '08:30', _cafe, 190, 'Кофе с собой'),
    _Spend(25, '19:10', _food, 560, 'ВкусВилл'),
    _Spend(26, '13:00', _health, 330, 'Витамины'),
    _Spend(27, '23:10', _transport, 860, 'Такси'),
    _Spend(28, '14:00', _cafe, 410, 'Бургер'),
    _Spend(29, '12:00', _food, 990, 'Ашан'),
    _Spend(30, '20:00', _fun, 349, 'Онлайн-кинотеатр'),
    _Spend(31, '08:30', _cafe, 190, 'Кофе с собой'),
    _Spend(31, '18:00', _transport, 70, ''),
  ]),
  _SeedMonth(YearMonth(2026, 9), const [
    _Spend(1, '08:30', _cafe, 190, 'Кофе с собой'),
    _Spend(1, '09:00', _gifts, 1200, 'Цветы на 1 сентября'),
    _Spend(2, '10:00', _phone, 600, 'Мобильная связь'),
    _Spend(2, '19:30', _food, 740, 'Пятёрочка'),
    _Spend(3, '13:15', _cafe, 680, 'Обед с коллегами'),
    _Spend(4, '08:00', _transport, 450, 'Пополнение Тройки'),
    _Spend(4, '21:00', _cafe, 550, 'Ужин в кафе'),
    _Spend(5, '12:00', _food, 2130, 'Ашан'),
    _Spend(5, '12:20', _home, 890, 'Бытовая химия'),
    _Spend(6, '18:00', _fun, 700, 'Кино'),
    _Spend(7, '08:30', _cafe, 190, 'Кофе с собой'),
    _Spend(7, '19:00', _food, 380, 'ВкусВилл'),
    _Spend(8, '17:00', _health, 1240, 'Аптека'),
    _Spend(9, '08:30', _cafe, 210, 'Кофе с собой'),
    _Spend(10, '09:00', _phone, 500, 'Домашний интернет'),
    _Spend(10, '19:40', _food, 620, 'Пятёрочка'),
    _Spend(11, '23:30', _transport, 640, 'Такси'),
    _Spend(12, '11:00', _sport, 2900, 'Абонемент в зал'),
    _Spend(12, '13:00', _food, 1560, 'Ашан'),
    _Spend(14, '08:30', _cafe, 190, 'Кофе с собой'),
    _Spend(15, '19:10', _food, 470, ''),
    _Spend(16, '13:30', _cafe, 750, 'Обед с коллегами'),
    _Spend(17, '19:00', _transport, 120, 'Метро, 2 поездки'),
    _Spend(18, '21:00', _cafe, 1300, 'Пицца с друзьями'),
    _Spend(19, '12:00', _food, 1200, 'Ашан'),
    _Spend(21, '08:30', _cafe, 190, 'Кофе с собой'),
    _Spend(23, '20:00', _food, 349, 'Молоко и хлеб', kopecks: 90),
    _Spend(24, '18:00', _health, 420, 'Витамины'),
    _Spend(26, '12:30', _food, 1180, 'Ашан'),
    _Spend(27, '16:00', _clothes, 2300, 'Джинсы'),
    _Spend(28, '08:00', _transport, 450, 'Пополнение Тройки'),
    _Spend(30, '22:00', _fun, 299, 'Онлайн-кинотеатр'),
  ]),
  _SeedMonth(YearMonth(2026, 10), const [
    _Spend(1, '08:30', _cafe, 180, 'Кофе с собой'),
    _Spend(1, '19:30', _transport, 100, 'Автобус, 2 поездки'),
    _Spend(1, '20:10', _food, 170, 'Хлеб и молоко'),
    _Spend(2, '08:50', _food, 200, 'Пекарня'),
    _Spend(2, '10:00', _phone, 600, 'Мобильная связь'),
    _Spend(2, '19:00', _food, 480, 'Пятёрочка'),
    _Spend(3, '10:30', _cafe, 170, 'Кофе с собой'),
    _Spend(3, '12:00', _food, 1180, 'Ашан'),
    _Spend(3, '12:05', _food, 240, 'Вода и соки'),
    _Spend(3, '12:50', _food, 230, 'Овощи на рынке'),
    _Spend(3, '18:00', _fun, 520, 'Боулинг'),
    _Spend(5, '23:10', _transport, 860, 'Такси'),
    _Spend(6, '09:00', _cafe, 260, 'КОФЕ И ПИРОГ'),
    _Spend(6, '18:30', _transport, 60, 'Метро'),
    _Spend(7, '08:00', _transport, 450, 'Пополнение Тройки'),
    _Spend(8, '15:00', _health, 1090, 'Аптека'),
    _Spend(8, '18:30', _food, 60, 'Хлеб'),
    _Spend(9, '08:40', _food, 150, 'Пекарня'),
    _Spend(9, '18:00', _food, 390, 'ВкусВилл'),
    _Spend(10, '09:40', _cafe, 170, 'Кофе с собой'),
    _Spend(10, '11:30', _food, 520, 'Пятёрочка'),
    _Spend(10, '11:35', _food, 170, 'Молоко'),
    _Spend(10, '11:45', _food, 300, 'Фрукты'),
    _Spend(10, '12:00', _phone, 500, 'Домашний интернет'),
    _Spend(10, '19:00', _fun, 450, 'Квиз'),
    _Spend(10, '22:00', _cafe, 560, 'Пицца с друзьями'),
    _Spend(11, '10:20', _cafe, 190, 'Кофе с собой'),
    _Spend(11, '16:00', _fun, 270, 'Онлайн-кинотеатр'),
    _Spend(11, '20:00', _food, 380, 'Пятёрочка'),
    _Spend(11, '20:05', _food, 150, 'Сыр'),
    _Spend(12, '11:00', _sport, 2900, 'Абонемент в зал'),
    _Spend(13, '08:15', _cafe, 120, 'Кофе с собой'),
    _Spend(13, '16:30', _cafe, 90, 'Печенье к чаю'),
    _Spend(15, '08:40', _cafe, 340, 'Кофе и круассан'),
    _Spend(15, '17:00', _food, 300, 'Кофе в зёрнах'),
    _Spend(15, '17:05', _food, 120, 'Шоколад'),
    _Spend(16, '22:40', _transport, 430, 'Такси'),
    _Spend(17, '13:30', _cafe, 890, 'Обед с коллегами'),
    _Spend(17, '19:10', _food, 560, 'ВкусВилл'),
    _Spend(18, '20:00', _fun, 400, 'Кино 50% скидка'),
    _Spend(19, '09:15', _cafe, 210, 'Кофе с собой'),
    _Spend(19, '12:40', _transport, 250, 'Метро, 2 поездки'),
    _Spend(19, '18:40', _food, 640, 'Пятёрочка'),
  ]),
];
