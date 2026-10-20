import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/data/dev_seed.dart';
import 'package:shared/shared.dart';

import 'repositories/repository_harness.dart';

const Map<String, int> _empty = {
  'budgets': 0,
  'categories': 0,
  'expenses': 0,
  'recurring_rules': 0,
  'outbox': 0,
};

void main() {
  late RepositoryHarness h;

  setUp(() => h = RepositoryHarness());

  tearDown(() => h.dispose());

  DevSeed seed() => DevSeed(h.db, currentUser: h.user);

  List<String> seedLines([Level level = Level.ALL]) => [
    for (final r in h.records)
      if (r.loggerName == 'seed' && r.level >= level) formatLogRecord(r),
  ];

  test('без --dart-define=DEV_SEED флаг пустой: сида нет, база пуста, '
      'ни строки [seed]', () async {
    final result = await seed().runIfRequested();

    expect(devSeedDefine, isEmpty);
    expect(result.status, DevSeedStatus.off);
    expect(await h.rowCounts(), _empty);
    expect(seedLines(), isEmpty);
  });

  test('DEV_SEED=true вне debug (release, profile): сида нет, '
      'одно предупреждение', () async {
    final result = await seed().runIfRequested(flag: 'true', debugBuild: false);

    expect(result.status, DevSeedStatus.ignored);
    expect(await h.rowCounts(), _empty);
    expect(seedLines(), [
      endsWith(
        'WARN  [seed] DEV_SEED=true ignored: works only in debug builds',
      ),
    ]);
  });

  test('другое значение DEV_SEED в debug: сида нет, предупреждение '
      'с подсказкой', () async {
    for (final flag in ['1', 'TRUE', 'yes']) {
      final result = await seed().runIfRequested(flag: flag, debugBuild: true);

      expect(result.status, DevSeedStatus.ignored, reason: flag);
    }

    expect(await h.rowCounts(), _empty);
    expect(seedLines(), [
      for (final flag in ['1', 'TRUE', 'yes'])
        endsWith(
          'WARN  [seed] DEV_SEED=$flag ignored: only DEV_SEED=true turns '
          'the dev seed on',
        ),
    ]);
  });

  test('повторный запуск на заполненной базе ничего не добавляет: те же '
      'строки и outbox, в логе «пропуск»', () async {
    final first = await seed().runIfRequested(flag: 'true', debugBuild: true);
    final counts = await h.rowCounts();
    final outbox = [for (final o in await h.outboxRows()) o.id];
    h.records.clear();

    final second = await seed().runIfRequested(flag: 'true', debugBuild: true);

    expect(first.status, DevSeedStatus.seeded);
    expect(
      [first.budgets, first.categories, first.expenses],
      [1, 11, counts['expenses']],
    );
    expect(counts['expenses'], greaterThan(0));
    expect(second.status, DevSeedStatus.skipped);
    expect(await h.rowCounts(), counts);
    expect([for (final o in await h.outboxRows()) o.id], outbox);
    expect(seedLines(Level.INFO), [
      contains('INFO  [seed] dev seed requested DEV_SEED=true'),
      matches(
        RegExp(
          r'INFO  \[seed\] dev seed skipped: database not empty budgets=1 '
          'categories=11 expenses=${counts['expenses']} recurring=0 '
          r'in \d+ms$',
        ),
      ),
    ]);
  });

  test('база с данными с сервера: пропуск, свой личный бюджет и траты '
      'не создаются', () async {
    await h.seedBudget(id: 'budget-from-server');
    final before = await h.rowCounts();

    final result = await seed().runIfRequested(flag: 'true', debugBuild: true);

    expect(result.status, DevSeedStatus.skipped);
    expect(await h.rowCounts(), before);
    expect(before['outbox'], 0);
    expect(
      [for (final b in await h.budgets.watchAll().first) b.id],
      ['budget-from-server'],
    );
  });
}
