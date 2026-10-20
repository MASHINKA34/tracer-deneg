import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/data/dev_seed.dart';
import 'package:shared/shared.dart';

import 'repositories/repository_harness.dart';

const List<String> _comments = [
  'Обед с коллегами',
  'ВкусВилл',
  'Пятёрочка',
  'Ремонт ноутбука',
  'Кофе',
];

const List<String> _namesAndAmounts = [
  'Продукты',
  'Кафе',
  '19000',
  '89000',
  '640000',
  '1830000',
];

void _expectNoSecrets(Iterable<String> lines, List<String> secrets) {
  for (final line in lines) {
    for (final secret in secrets) {
      expect(
        line.toLowerCase(),
        isNot(contains(secret.toLowerCase())),
        reason: '$secret in $line',
      );
    }
  }
}

void main() {
  late RepositoryHarness h;

  setUp(() async {
    h = RepositoryHarness();
    await h.db.customSelect('SELECT 1').get();
    h.records.clear();
  });

  tearDown(() => h.dispose());

  Future<DevSeedResult> run() => DevSeed(
    h.db,
    currentUser: h.user,
  ).runIfRequested(flag: 'true', debugBuild: true);

  List<String> lines(Level from, [Level to = Level.SHOUT]) => [
    for (final r in h.records)
      if (r.level >= from && r.level <= to) formatLogRecord(r),
  ];

  test(
    'итог сида на info: старт, личный бюджет, итог с числами и мс, '
    'одна строка размера outbox - без комментариев, сумм и названий',
    () async {
      final result = await run();
      final info = lines(Level.INFO);

      expect(result.status, DevSeedStatus.seeded);
      expect(info, [
        endsWith(
          'INFO  [seed] dev seed requested DEV_SEED=true build=debug '
          'months=2026-08..2026-10',
        ),
        matches(
          RegExp(
            r'INFO  \[repo\] personal budget created id=\S+ categories=11 '
            r'outbox=12 in \d+ms$',
          ),
        ),
        matches(
          RegExp(
            r'INFO  \[seed\] dev seed done budgets=1 categories=11 '
            'expenses=${result.expenses} months=3 '
            'outbox=${result.expenses + 12} '
            r'budget=\S+ in \d+ms$',
          ),
        ),
        endsWith(
          'INFO  [repo] outbox size=${result.expenses + 12} was=- '
          'after=dev-seed',
        ),
      ]);
      _expectNoSecrets(info, [..._comments, ..._namesAndAmounts]);
    },
  );

  test('на debug: прогресс по каждому месяцу - число трат и сумма '
      'в копейках, без комментариев', () async {
    await run();
    final months = [
      for (final line in lines(Level.ALL, Level.FINE))
        if (line.contains('[seed] dev seed month=')) line,
    ];

    expect(months, [
      for (final m in ['2026-08', '2026-09', '2026-10'])
        matches(
          RegExp(
            'DEBUG \\[seed\\] dev seed month=$m expenses=\\d+ '
            'totalKopecks=\\d+ in \\d+ms\$',
          ),
        ),
    ]);
    expect(months.last, contains('totalKopecks=1830000'));
    _expectNoSecrets(months, _comments);
  });

  test('сбой посреди сида: error со стеком, шагом и типом без комментариев '
      'и сумм, всё откатилось, следующий запуск сидирует заново', () async {
    await h.db.customStatement(
      'CREATE TRIGGER expenses_broken BEFORE INSERT ON expenses '
      'WHEN (SELECT count(*) FROM expenses) >= 5 '
      "BEGIN SELECT RAISE(ABORT, 'expenses is broken'); END",
    );

    final failed = await run();
    final errors = [
      for (final r in h.records)
        if (r.loggerName == 'seed' && r.level >= Level.SEVERE)
          formatLogRecord(r),
    ];

    expect(failed.status, DevSeedStatus.failed);
    expect(await h.rowCounts(), {
      'budgets': 0,
      'categories': 0,
      'expenses': 0,
      'recurring_rules': 0,
      'outbox': 0,
    });
    expect(errors, hasLength(1));
    final line = errors.single;
    expect(
      line,
      contains(
        'ERROR [seed] dev seed failed step=expenses month=2026-08 created=5 ',
      ),
    );
    expect(line, contains('seed rolled back, nothing seeded'));
    expect(line, contains('SqliteException(1811)'));
    expect(line, contains('expenses is broken'));
    expect(line, contains('parameters: <'));
    final stack = line.indexOf('\n  stack:\n');
    expect(stack, greaterThan(0));
    expect(line.substring(stack), contains('package:milionchik/data/'));
    _expectNoSecrets([line], [..._comments, ..._namesAndAmounts]);

    await h.db.customStatement('DROP TRIGGER expenses_broken');
    final retry = await run();

    expect(retry.status, DevSeedStatus.seeded);
    expect((await h.rowCounts())['expenses'], retry.expenses);
  });
}
