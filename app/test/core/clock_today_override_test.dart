import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/core/clock.dart';
import 'package:milionchik/data/db/app_database.dart';
import 'package:milionchik/data/providers.dart';
import 'package:milionchik/data/repositories/prefs_repository.dart';
import 'package:shared/shared.dart';

final class _BrokenPrefs extends Fake implements PrefsRepository {
  _BrokenPrefs(this.error);

  final Object error;

  @override
  Future<String?> getString(String key) async => throw error;

  @override
  Future<void> setString(String key, String value) async => throw error;

  @override
  Future<void> remove(String key) async => throw error;
}

SqliteException _sqlError(String value) => SqliteException(
  extendedResultCode: 10,
  message: 'disk I/O error',
  causingStatement:
      'INSERT OR REPLACE INTO local_prefs (key, value) '
      'VALUES (?, ?)',
  parametersToStatement: [PrefKeys.todayOverride, value],
);

void main() {
  late List<LogRecord> records;
  late StreamSubscription<LogRecord> sub;

  setUp(() {
    records = [];
    Logger.root.level = Level.ALL;
    sub = Logger.root.onRecord.listen(records.add);
  });

  tearDown(() => sub.cancel());

  List<String> clockLines([Level level = Level.ALL]) => [
    for (final r in records)
      if (r.loggerName == 'clock' && r.level >= level) formatLogRecord(r),
  ];

  LocalDate realToday() => LocalDate.fromDateTime(DateTime.now());

  ProviderContainer containerWith(
    AppDatabase db, [
    List<Override> more = const [],
  ]) => ProviderContainer.test(
    overrides: [appDatabaseProvider.overrideWithValue(db), ...more],
  );

  test('подменённая дата видна через clockProvider и лежит в local_prefs; '
      'сброс возвращает настоящую дату и убирает запись', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    final container = containerWith(db);
    final prefs = DriftPrefsRepository(db);
    final halloween = LocalDate(2026, 10, 31);

    expect(container.read(clockProvider).today(), realToday());

    expect(
      await container.read(todayOverrideProvider.notifier).set(halloween),
      isTrue,
    );

    final clock = container.read(clockProvider);
    expect(clock.today(), halloween);
    final now = clock.now();
    final real = DateTime.now();
    expect(LocalDate.fromDateTime(now), halloween);
    expect(now.hour, real.hour);
    expect(now.minute, real.minute);
    expect(await prefs.getString(PrefKeys.todayOverride), '2026-10-31');
    expect(clockLines(Level.INFO), [
      matches(
        RegExp(
          r'INFO  \[clock\] today override set date=2026-10-31 '
          'real=${realToday()} previous=none in \\d+ms \\(debug build\\)\$',
        ),
      ),
    ]);

    records.clear();
    expect(
      await container.read(todayOverrideProvider.notifier).reset(),
      isTrue,
    );

    expect(container.read(clockProvider).today(), realToday());
    expect(container.read(todayOverrideProvider), isNull);
    expect(await prefs.getString(PrefKeys.todayOverride), isNull);
    expect(clockLines(Level.INFO), [
      matches(
        RegExp(
          r'INFO  \[clock\] today override reset date=2026-10-31 → real date '
          '${realToday()} in \\d+ms \\(debug build\\)\$',
        ),
      ),
    ]);
  });

  test(
    'подмена доходит до репозиториев: бюджет создан в подменённый день',
    () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      final container = containerWith(db);
      final day = LocalDate(2026, 12, 31);

      await container.read(todayOverrideProvider.notifier).set(day);
      final budget = await container
          .read(budgetsRepositoryProvider)
          .createLocalPersonal();

      expect(LocalDate.fromDateTime(budget.createdAt.toLocal()), day);
    },
  );

  test('вне debug-сборки clockFor отдаёт настоящие часы даже с подменой', () {
    final halloween = LocalDate(2026, 10, 31);

    expect(clockFor(halloween, debugBuild: false).today(), realToday());
    expect(clockFor(null, debugBuild: false).today(), realToday());
    expect(clockFor(halloween, debugBuild: true).today(), halloween);
    expect(clockFor(null, debugBuild: true).today(), realToday());
  });

  test('сохранить подмену не удалось — часы прежние, warn [clock] без '
      'значений параметров SQL', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    final container = containerWith(db, [
      prefsRepositoryProvider.overrideWithValue(
        _BrokenPrefs(_sqlError('2026-10-31')),
      ),
    ]);

    expect(
      await container
          .read(todayOverrideProvider.notifier)
          .set(LocalDate(2026, 10, 31)),
      isFalse,
    );

    expect(container.read(clockProvider).today(), realToday());
    expect(container.read(todayOverrideProvider), isNull);
    final line = clockLines(Level.WARNING).single;
    expect(
      line,
      matches(
        RegExp(
          r'^\S+ WARN  \[clock\] today override set date=2026-10-31 not saved '
          r'after \d+ms, keeping real date: SqliteException',
        ),
      ),
    );
    expect(line, contains('disk I/O error'));
    expect(line, contains('parameters: <text:18>, <text:10>'));
    expect(line, isNot(contains('parameters: debugTodayOverride')));
    expect(clockLines(Level.INFO).where((l) => l.contains('INFO')), isEmpty);
  });

  test('сбросить не удалось — подмена остаётся, warn [clock]', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    final halloween = LocalDate(2026, 10, 31);
    final container = containerWith(db, [
      todayOverrideProvider.overrideWithBuild((ref, _) => halloween),
      prefsRepositoryProvider.overrideWithValue(
        _BrokenPrefs(StateError('prefs closed')),
      ),
    ]);

    expect(
      await container.read(todayOverrideProvider.notifier).reset(),
      isFalse,
    );

    expect(container.read(clockProvider).today(), halloween);
    expect(clockLines(Level.WARNING), [
      matches(
        RegExp(
          r'WARN  \[clock\] today override reset not saved after \d+ms, '
          r'keeping 2026-10-31: StateError: Bad state: prefs closed',
        ),
      ),
    ]);
  });

  group('чтение при старте', () {
    test('сохранённая дата → она и warn «today overridden»', () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      final prefs = DriftPrefsRepository(db);
      await prefs.setString(PrefKeys.todayOverride, '2026-10-31');
      records.clear();

      expect(await loadTodayOverride(prefs), LocalDate(2026, 10, 31));

      expect(clockLines(), [
        matches(
          RegExp(
            r'WARN  \[clock\] today overridden date=2026-10-31 '
            'real=${realToday()} key=debugTodayOverride in \\d+ms: debug '
            r'build, reset it in the catalog$',
          ),
        ),
      ]);
    });

    test('записи нет → null и только debug-строка', () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);

      expect(await loadTodayOverride(DriftPrefsRepository(db)), isNull);

      expect(clockLines(), [
        matches(
          RegExp(
            r'DEBUG \[clock\] today override: none, real date '
            '${realToday()} in \\d+ms\$',
          ),
        ),
      ]);
    });

    test('в записи не дата → null и warn без значения', () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      final prefs = DriftPrefsRepository(db);
      await prefs.setString(PrefKeys.todayOverride, '31.10.2026');
      records.clear();

      expect(await loadTodayOverride(prefs), isNull);

      final line = clockLines().single;
      expect(
        line,
        matches(
          RegExp(
            r'WARN  \[clock\] today override ignored: key=debugTodayOverride '
            r'is not a YYYY-MM-DD date length=10, starting with real date '
            '${realToday()}\$',
          ),
        ),
      );
      expect(line, isNot(contains('31.10.2026')));
    });

    test(
      'чтение упало → null, warn с типом ошибки и без параметров SQL',
      () async {
        expect(
          await loadTodayOverride(_BrokenPrefs(_sqlError('2026-10-31'))),
          isNull,
        );

        final line = clockLines(Level.WARNING).single;
        expect(
          line,
          matches(
            RegExp(
              r'WARN  \[clock\] today override read failed after \d+ms, '
              'starting with real date ${realToday()}: SqliteException',
            ),
          ),
        );
        expect(line, contains('parameters: <text:18>, <text:10>'));
        expect(line, isNot(contains('parameters: debugTodayOverride')));
      },
    );
  });
}
