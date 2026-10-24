import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/core/clock.dart';
import 'package:milionchik/data/api/api_providers.dart';
import 'package:milionchik/data/db/app_database.dart';
import 'package:milionchik/data/providers.dart';
import 'package:milionchik/data/repositories/outbox_queue.dart';
import 'package:milionchik/data/session/session.dart';
import 'package:milionchik/data/session/session_providers.dart';
import 'package:milionchik/data/session/session_state.dart';
import 'package:milionchik/data/sync/pull_controller.dart';
import 'package:milionchik/data/sync/pull_service.dart';
import 'package:milionchik/data/sync/sync_engine.dart';
import 'package:shared/shared.dart';

import '../api/fake_api_adapter.dart';
import 'pull_fixture.dart';

const _user = SessionUser(
  userId: pullUserId,
  login: 'anya_m',
  displayName: 'Аня',
);

void main() {
  late LogCapture logs;
  late AppDatabase db;

  setUp(() {
    logs = LogCapture();
    db = AppDatabase.memory();
  });

  tearDown(() async {
    await logs.dispose();
    await db.close();
  });

  final personal = serverPersonal();
  final presets = serverPresets(personal.id);
  final rule = RecurringRule(
    id: 'rule-after-sync',
    budgetId: personal.id,
    categoryId: presets[3].id,
    title: 'podpiska-whiskey-xray',
    amount: Money.rubles(299),
    dayOfMonth: 5,
    startMonth: YearMonth(2026, 10),
    createdAt: pullT0,
    updatedAt: pullT0,
    updatedBy: pullUserId,
    seq: 40,
  );
  final chargeId = recurringExpenseId(rule.id, YearMonth(2026, 10));

  FakePullServer server() => FakePullServer([
    SyncPullResponse(
      budgets: [personal],
      members: [ownerOf(personal.id)],
      categories: presets,
      recurring: [rule],
      cursor: 40,
      hasMore: false,
    ),
  ]);

  ProviderContainer container(FakePullServer server) => ProviderContainer.test(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      clockProvider.overrideWithValue(
        Clock(now: () => DateTime(2026, 10, 19, 18, 40)),
      ),
      apiClientProvider.overrideWith((ref) => pullApiClient(server)),
      sessionProvider.overrideWithBuild((ref, _) => const SessionActive(_user)),
    ],
  );

  Future<ExpenseEntry?> charge() => (db.select(
    db.expenses,
  )..where((e) => e.id.equals(chargeId))).getSingleOrNull();

  List<String> generatorRuns() => [
    for (final line in logs.linesOf('recurring', Level.INFO))
      if (line.contains('run (after sync)')) line,
  ];

  test('цикл движка: pull принёс правило с днём 5 - после pull генератор '
      '«after sync» создал трату октября, она в очереди на отправку', () async {
    final fake = server();
    final c = container(fake);

    final result = await c.read(syncEngineProvider).sync(SyncReason.manual);

    expect(result, isA<SyncCycleDone>());
    final created = await charge();
    expect(created, isNotNull);
    expect(created!.recurringId, rule.id);
    expect(created.spentOn, LocalDate(2026, 10, 5));
    expect(await DriftOutboxQueue(db).count(), 1);
    expect(c.read(syncEngineProvider).state.queueSize, 1);
    expect(generatorRuns(), [
      contains('run (after sync) today=2026-10-19 rules=1 created=1'),
    ]);
    expect(
      logs.linesOf('sync', Level.FINE),
      containsAllInOrder([
        endsWith(
          'sync cycle manual: pull applied pages=1 entities=${1 + 1 + presets.length + 1} '
          'recurring=1 → recurring generator (after sync)',
        ),
        matches(
          RegExp(
            r'sync cycle manual: recurring generator \(after sync\) finished '
            r'in \d+ms$',
          ),
        ),
      ]),
    );
  });

  test('первая загрузка после входа (pull без push) тоже запускает '
      'генератор после pull', () async {
    final fake = server();
    final c = container(fake);

    final pulled = await c
        .read(pullControllerProvider.notifier)
        .run(PullReason.login);

    expect(pulled, isNotNull);
    expect(await charge(), isNotNull);
    expect(generatorRuns(), hasLength(1));
    expect(
      logs.linesOf('sync', Level.FINE),
      contains(
        endsWith(
          'sync pull login: pull applied pages=1 entities=${1 + 1 + presets.length + 1} '
          'recurring=1 → recurring generator (after sync)',
        ),
      ),
    );
  });

  test('pull не удался - генератор после синхронизации не запускается; '
      'следующий удачный цикл - запускается один раз', () async {
    final fake = server();
    var down = true;
    fake.before[1] = (call) =>
        down ? throw const SocketException('Network is unreachable') : null;
    final c = container(fake);

    final result = await c.read(syncEngineProvider).sync(SyncReason.manual);

    expect(result, isA<SyncCycleFailed>());
    expect(await charge(), isNull);
    expect(generatorRuns(), isEmpty);
    expect(
      logs.linesOf('sync', Level.FINE),
      isNot(contains(contains('recurring generator (after sync)'))),
    );

    down = false;
    final again = await c.read(syncEngineProvider).sync(SyncReason.manual);

    expect(again, isA<SyncCycleDone>());
    expect(await charge(), isNotNull);
    expect(generatorRuns(), hasLength(1));
  });
}
