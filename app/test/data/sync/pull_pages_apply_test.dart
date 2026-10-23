import 'dart:io';

import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/data/api/api_exception.dart';
import 'package:milionchik/data/db/app_database.dart';
import 'package:milionchik/data/queries/month_queries.dart';
import 'package:milionchik/data/sync/pull_service.dart';
import 'package:shared/shared.dart';

import '../api/fake_api_adapter.dart';
import 'pull_fixture.dart';

const String _secretComment = 'Тайный-комментарий-Альфа-Браво';

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
  final food = presets.first;

  List<SyncPullResponse> threePages() => [
    SyncPullResponse(
      budgets: [personal],
      members: [ownerOf(personal.id)],
      categories: presets,
      cursor: 12,
      hasMore: true,
    ),
    SyncPullResponse(
      expenses: [
        serverExpense(
          id: 'e-1',
          budgetId: personal.id,
          categoryId: food.id,
          seq: 13,
        ),
        serverExpense(
          id: 'e-2',
          budgetId: personal.id,
          categoryId: food.id,
          kopecks: 15000,
          seq: 14,
        ),
      ],
      cursor: 14,
      hasMore: true,
    ),
    SyncPullResponse(
      recurring: [
        RecurringRule(
          id: 'r-1',
          budgetId: personal.id,
          categoryId: food.id,
          title: 'Интернет',
          amount: Money(70000),
          dayOfMonth: 5,
          startMonth: YearMonth(2026, 10),
          createdAt: pullT0,
          updatedAt: pullT0,
          updatedBy: pullUserId,
          seq: 15,
        ),
      ],
      expenses: [
        serverExpense(
          id: 'e-3',
          budgetId: personal.id,
          categoryId: food.id,
          kopecks: 9900,
          seq: 16,
        ),
      ],
      cursor: 16,
      hasMore: false,
    ),
  ];

  test(
    'три страницы: каждая применяется своей транзакцией, курсор '
    'сохраняется после каждой, lastSyncAt и сводка - после последней',
    () async {
      final server = FakePullServer(threePages());
      final rig = PullRig(db, server);
      final seenBeforePage = <int, (int, int, DateTime?)>{};
      for (final page in [2, 3]) {
        server.before[page] = (call) async {
          final state = await rig.syncState();
          seenBeforePage[page] = (
            state.cursor,
            await rig.count('categories'),
            state.lastSyncAt,
          );
          return null;
        };
      }

      final result = await rig.service().pull(PullReason.login);

      expect(server.cursors, [0, 12, 14]);
      expect(seenBeforePage[2], (12, 11, null));
      expect(seenBeforePage[3], (14, 11, null));
      final state = await rig.syncState();
      expect(state.cursor, 16);
      expect(state.lastSyncAt, DateTime.utc(2026, 10, 19, 15, 40));
      expect(state.lastError, isNull);
      expect(await rig.count('budgets'), 1);
      expect(await rig.count('budget_members'), 1);
      expect(await rig.count('categories'), 11);
      expect(await rig.count('expenses'), 3);
      expect(await rig.count('recurring_rules'), 1);
      expect(await rig.count('outbox'), 0);
      expect(result.pages, 3);
      expect(result.cursorBefore, 0);
      expect(result.cursorAfter, 16);
      expect(
        result.counts,
        const PullCounts(
          budgets: 1,
          members: 1,
          categories: 11,
          expenses: 3,
          recurring: 1,
        ),
      );

      final info = logs.linesOf('sync', Level.INFO);
      expect(info, hasLength(1));
      expect(
        info.single,
        matches(
          RegExp(
            r'INFO  \[sync\] pull done reason=login pages=3 entities=17 '
            r'budgets=1 members=1 profiles=0 categories=11 expenses=3 '
            r'recurring=1 removed=0 cursor=0→16 in \d+ms$',
          ),
        ),
      );
      expect(
        logs.linesOf('sync', Level.FINE),
        containsAllInOrder([
          contains('pull start reason=login cursor=0 limit=500 attempt=1'),
          matches(
            RegExp(
              r'pull page 1 applied in one transaction entities=13 budgets=1 '
              r'members=1 .*cursor=0→12 hasMore=true in \d+ms '
              r'rid=ridpull000000001$',
            ),
          ),
          contains('pull page 2 applied in one transaction entities=2'),
          matches(RegExp(r'pull page 3 .*cursor=14→16 hasMore=false')),
        ]),
      );
      for (final secret in [pullAccess, pullRefresh, 'Интернет']) {
        expect(logs.text, isNot(contains(secret)), reason: secret);
      }
    },
  );

  test('обрыв сети на 2-й странице: 1-я остаётся с курсором, повтор '
      'начинается со 2-й, warn с типом, rid и попыткой', () async {
    final server = FakePullServer(threePages());
    final rig = PullRig(db, server);
    server.before[2] = (call) =>
        throw const SocketException('Connection refused (test)');

    final failure = await rig
        .service()
        .pull(PullReason.manual, attempt: 2)
        .then<PullFailure?>(
          (_) => null,
          onError: (Object e) => e as PullFailure,
        );

    expect(failure, isNotNull);
    expect(failure!.stage, PullStage.request);
    expect(failure.page, 2);
    expect(failure.cursor, 12);
    expect(failure.pagesApplied, 1);
    expect(failure.attempt, 2);
    expect(failure.error, isA<ApiNetworkFailure>());
    final state = await rig.syncState();
    expect(state.cursor, 12);
    expect(state.lastSyncAt, isNull);
    expect(
      state.lastError,
      startsWith('request ApiNetworkFailure: connection'),
    );
    expect(await rig.count('budgets'), 1);
    expect(await rig.count('categories'), 11);
    expect(await rig.count('expenses'), 0);
    expect(
      _messages(logs, Level.WARNING),
      contains(
        matches(
          RegExp(
            r'^pull failed reason=manual stage=request page=2 cursor=12 '
            r'attempt=2 ApiNetworkFailure: connection cause=SocketException: '
            r'Connection refused \(test\) rid=ridpull000000002 after \d+ms → '
            r'1 page\(s\) applied and kept, page 2 not received, local data '
            r'kept$',
          ),
        ),
      ),
    );

    server.before.remove(2);
    final retry = await rig.service().pull(PullReason.retry);

    expect(server.cursors, [0, 12, 12, 14]);
    expect(retry.cursorBefore, 12);
    expect(retry.cursorAfter, 16);
    expect(retry.pages, 2);
    expect(await rig.count('expenses'), 3);
    expect((await rig.syncState()).lastError, isNull);
  });

  test('2-я страница не записалась: вся страница откатывается, курсор не '
      'двигается, в логе ошибки нет комментария и значений SQL', () async {
    final pages = threePages();
    pages[1] = SyncPullResponse(
      budgets: [serverShared(seq: 13)],
      categories: serverPresets('budget-family', firstSeq: 14).take(1).toList(),
      expenses: [
        serverExpense(
          id: 'e-secret',
          budgetId: personal.id,
          categoryId: food.id,
          comment: _secretComment,
          seq: 15,
        ),
      ],
      cursor: 15,
      hasMore: true,
    );
    final server = FakePullServer(pages);
    final rig = PullRig(db, server);
    server.before[2] = (call) async {
      await db.customStatement(
        'CREATE TRIGGER fail_expense BEFORE INSERT ON expenses '
        "BEGIN SELECT RAISE(ABORT, 'disk is full (test)'); END",
      );
      return null;
    };

    final failure = await rig
        .service()
        .pull(PullReason.login)
        .then<PullFailure?>(
          (_) => null,
          onError: (Object e) => e as PullFailure,
        );

    expect(failure!.stage, PullStage.apply);
    expect(failure.page, 2);
    expect(failure.pagesApplied, 1);
    expect(server.cursors, [0, 12]);
    final state = await rig.syncState();
    expect(state.cursor, 12);
    expect(state.lastSyncAt, isNull);
    expect(state.lastError, contains('apply SqliteException'));
    expect(await rig.count('budgets'), 1);
    expect(await rig.count('categories'), 11);
    expect(await rig.count('expenses'), 0);

    final severe = _messages(logs, Level.SEVERE);
    expect(severe, hasLength(1));
    expect(
      severe.single,
      allOf(
        startsWith(
          'pull failed reason=login stage=apply page=2 cursor=12 attempt=1 '
          'SqliteException: ',
        ),
        contains('disk is full (test)'),
        contains('parameters: <text:'),
        matches(
          RegExp(
            r'rid=ridpull000000002 after \d+ms → 1 page\(s\) applied and '
            r'kept, page 2 rolled back, local data kept$',
          ),
        ),
      ),
    );
    final errors = [
      for (final r in logs.records)
        if (r.error != null) '${r.error}',
    ];
    expect(errors, isNotEmpty);
    for (final text in [logs.text, ...errors, state.lastError!]) {
      expect(text, isNot(contains(_secretComment)));
      expect(text, isNot(contains('Семья')));
    }
  });

  test('надгробия с сервера убирают трату и категорию из чтения', () async {
    final day = LocalDate(2026, 10, 19);
    final taxi = presets[3];
    final server = FakePullServer([
      SyncPullResponse(
        budgets: [personal],
        categories: presets,
        expenses: [
          serverExpense(
            id: 'e-1',
            budgetId: personal.id,
            categoryId: food.id,
            seq: 13,
          ),
          serverExpense(
            id: 'e-2',
            budgetId: personal.id,
            categoryId: taxi.id,
            kopecks: 30000,
            seq: 14,
          ),
        ],
        cursor: 14,
        hasMore: true,
      ),
      SyncPullResponse(
        categories: [
          taxi.copyWith(
            deletedAt: DateTime.utc(2026, 10, 19, 12),
            updatedAt: DateTime.utc(2026, 10, 19, 12),
            seq: 16,
          ),
        ],
        expenses: [
          serverExpense(
            id: 'e-2',
            budgetId: personal.id,
            categoryId: taxi.id,
            kopecks: 30000,
            deletedAt: DateTime.utc(2026, 10, 19, 12),
            seq: 15,
          ),
        ],
        cursor: 16,
        hasMore: false,
      ),
    ]);
    final rig = PullRig(db, server);
    final queries = DriftMonthQueries(db);

    await rig.service().pull(PullReason.login);

    final dayExpenses = await queries.watchDayExpenses(personal.id, day).first;
    expect([for (final e in dayExpenses) e.id], ['e-1']);
    expect(
      await queries.watchMonthTotal(personal.id, YearMonth(2026, 10)).first,
      Money(64000),
    );
    final live = await rig.categories(personal.id);
    expect(live, hasLength(10));
    expect(live, isNot(contains(taxi.id)));
  });

  test('removedBudgetIds: данные бюджета удаляются, личный остаётся', () async {
    final family = serverShared(seq: 13);
    final familyCategory = serverPresets(family.id, firstSeq: 14).first;
    final server = FakePullServer([
      SyncPullResponse(
        budgets: [personal, family],
        members: [
          ownerOf(personal.id),
          ownerOf(family.id, userId: 'user-other'),
        ],
        categories: [...presets, familyCategory],
        expenses: [
          serverExpense(
            id: 'e-family',
            budgetId: family.id,
            categoryId: familyCategory.id,
            seq: 15,
          ),
        ],
        cursor: 15,
        hasMore: true,
      ),
      SyncPullResponse(
        removedBudgetIds: [family.id],
        cursor: 17,
        hasMore: false,
      ),
    ]);
    final rig = PullRig(db, server);

    final result = await rig.service().pull(PullReason.login);

    expect(result.counts.removed, 1);
    expect(await rig.count('budgets'), 1);
    expect(await rig.count('budget_members'), 1);
    expect(await rig.count('categories'), 11);
    expect(await rig.count('expenses'), 0);
    expect((await rig.syncState()).cursor, 17);
  });

  test('сервер ответил hasMore=true без движения курсора: остановка с '
      'ошибкой вместо бесконечного цикла', () async {
    final server = FakePullServer([
      SyncPullResponse(budgets: [personal], cursor: 5, hasMore: true),
    ]);
    server.before[2] = (call) => FakeReply.json(
      200,
      SyncPullResponse(cursor: 5, hasMore: true).toJson(),
    );
    final rig = PullRig(db, server);

    final failure = await rig
        .service()
        .pull(PullReason.login)
        .then<PullFailure?>(
          (_) => null,
          onError: (Object e) => e as PullFailure,
        );

    expect(failure!.error, isA<PullStalled>());
    expect(server.cursors, [0, 5]);
    expect((await rig.syncState()).cursor, 5);
    expect(
      _messages(logs, Level.SEVERE).single,
      contains(
        'pull failed reason=login stage=request page=2 cursor=5 attempt=1 '
        'PullStalled',
      ),
    );
  });
}

List<String> _messages(LogCapture logs, Level level) => [
  for (final r in logs.records)
    if (r.loggerName == 'sync' && r.level == level) r.message,
];

extension on PullRig {
  Future<List<String>> categories(String budgetId) async {
    final rows = await db
        .customSelect(
          'SELECT id FROM categories WHERE budget_id = ? '
          'AND deleted_at IS NULL',
          variables: [Variable.withString(budgetId)],
        )
        .get();
    return [for (final r in rows) r.read<String>('id')];
  }
}
