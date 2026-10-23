import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/data/db/app_database.dart';
import 'package:milionchik/data/repositories/account_data_cleaner.dart';
import 'package:milionchik/data/repositories/prefs_repository.dart';
import 'package:milionchik/data/sync/pull_service.dart';
import 'package:shared/shared.dart';

import '../../support/app_scope.dart';
import '../api/fake_api_adapter.dart';
import '../sync/pull_fixture.dart';

const String _secretComment = 'kommentariy-cleaner-hotel-india';

Future<int> _rows(AppDatabase db, String table) async {
  final row = await db
      .customSelect('SELECT COUNT(*) AS c FROM "$table"')
      .getSingle();
  return row.read<int>('c');
}

Future<void> _fillEverything(AppDatabase db) async {
  final personal = serverPersonal();
  final presets = serverPresets(personal.id);
  final rig = PullRig(
    db,
    FakePullServer([
      SyncPullResponse(
        budgets: [personal, serverShared(seq: 40)],
        members: [ownerOf(personal.id), ownerOf('budget-family')],
        profiles: const [
          MemberProfile(
            userId: pullUserId,
            displayName: 'Аня',
            avatarColor: CategoryColor.blue,
          ),
        ],
        categories: presets,
        recurring: [
          RecurringRule(
            id: 'r-1',
            budgetId: personal.id,
            categoryId: presets.first.id,
            title: 'Интернет',
            amount: const Money(70000),
            dayOfMonth: 5,
            startMonth: YearMonth(2026, 10),
            createdAt: pullT0,
            updatedAt: pullT0,
            updatedBy: pullUserId,
            seq: 41,
          ),
        ],
        expenses: [
          serverExpense(
            id: 'e-1',
            budgetId: personal.id,
            categoryId: presets.first.id,
            comment: _secretComment,
            seq: 42,
          ),
        ],
        cursor: 42,
        hasMore: false,
      ),
    ]),
  );
  await rig.service().pull(PullReason.login);
  await rig.outbox.enqueueDelete(SyncEntity.expense, 'e-1', at: pullT0);
  final prefs = DriftPrefsRepository(db);
  await prefs.setString(PrefKeys.themeMode, 'dark');
  await prefs.setBool(PrefKeys.signedInBefore, true);
  await prefs.setString(PrefKeys.todayOverride, '2026-10-19');
  await prefs.setString(PrefKeys.localUserId, 'local-user-1');
  await prefs.setString('holidaysHidden', 'halloween');
}

void main() {
  late LogCapture logs;

  setUp(() => logs = LogCapture());
  tearDown(() => logs.dispose());

  test('очищает все таблицы, курсор и время синхронизации; оставляет только '
      'настройки телефона', () async {
    final db = openTestDatabase();
    await _fillEverything(db);
    final tables = [for (final t in db.allTables) t.actualTableName];
    for (final table in tables) {
      expect(await _rows(db, table), greaterThan(0), reason: 'filled $table');
    }

    final removal = await DriftAccountDataCleaner(db)
        .clearAccountData('sign-out');

    final left = {for (final table in tables) table: await _rows(db, table)};
    expect(left, {
      for (final table in tables)
        table: switch (table) {
          'sync_state' => 1,
          'local_prefs' => 3,
          _ => 0,
        },
    });
    final state = await db.select(db.syncStates).getSingle();
    expect(
      (state.id, state.cursor, state.lastSyncAt, state.lastError),
      (0, 0, null, null),
    );
    final prefs = await db.select(db.localPrefs).get();
    expect(
      {for (final p in prefs) p.key: p.value},
      {
        PrefKeys.themeMode: 'dark',
        PrefKeys.signedInBefore: 'true',
        PrefKeys.todayOverride: '2026-10-19',
      },
    );
    expect(
      (
        removal.budgets,
        removal.members,
        removal.profiles,
        removal.categories,
        removal.expenses,
        removal.recurring,
        removal.outbox,
      ),
      (2, 2, 1, 11, 1, 1, 1),
    );
    expect(removal.prefs, ['holidaysHidden', PrefKeys.localUserId]);
    expect(removal.total, 21);
  });

  test('в логе - что очищено и мс, без комментариев и имён', () async {
    final db = openTestDatabase();
    await _fillEverything(db);
    logs.records.clear();

    await DriftAccountDataCleaner(db).clearAccountData('sign-out');

    expect(
      logs.linesOf('repo', Level.INFO),
      contains(
        matches(
          r'account data cleared reason=sign-out budgets=2 members=2 '
          r'profiles=1 categories=11 expenses=1 recurring=1 outbox=1 '
          r'syncState=reset prefs=\[holidaysHidden,localUserId\] '
          r'keptPrefs=\[debugTodayOverride,signedInBefore,themeMode\] '
          r'in \d+ms$',
        ),
      ),
    );
    expect(logs.text, isNot(contains(_secretComment)));
    expect(logs.text, isNot(contains('Аня')));
  });

  test('сбой посреди очистки: транзакция откатывается, ничего не удалено, '
      'severe с причиной, ошибка дальше', () async {
    final db = openTestDatabase();
    await _fillEverything(db);
    await db.customStatement(
      'CREATE TEMP TRIGGER keep_budgets BEFORE DELETE ON budgets '
      "BEGIN SELECT RAISE(ABORT, 'budgets locked'); END",
    );

    await expectLater(
      DriftAccountDataCleaner(db).clearAccountData('sign-out'),
      throwsA(anything),
    );

    expect(await _rows(db, 'expenses'), 1);
    expect(await _rows(db, 'outbox'), 1);
    expect(await _rows(db, 'budgets'), 2);
    expect(await _rows(db, 'local_prefs'), 5);
    expect(
      logs.linesOf('repo', Level.SEVERE),
      contains(
        allOf(
          contains('account data clear failed reason=sign-out after '),
          contains('transaction rolled back, nothing removed'),
          contains('budgets locked'),
        ),
      ),
    );
  });
}
