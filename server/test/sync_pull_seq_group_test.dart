import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/auth_support.dart';
import 'support/shared_budget_support.dart';
import 'support/sync_support.dart';
import 'support/test_support.dart';

class _Synced {
  _Synced.of(Iterable<SyncPullResponse> pages) {
    pages.forEach(_apply);
  }

  final budgets = <String, Budget>{};
  final members = <(String, String), BudgetMember>{};
  final profiles = <String, MemberProfile>{};
  final categories = <String, Category>{};
  final expenses = <String, Expense>{};
  final recurring = <String, RecurringRule>{};
  final removed = <String>{};

  void _apply(SyncPullResponse page) {
    budgets.addAll({for (final b in page.budgets) b.id: b});
    members.addAll({for (final m in page.members) (m.budgetId, m.userId): m});
    profiles.addAll({for (final p in page.profiles) p.userId: p});
    categories.addAll({for (final c in page.categories) c.id: c});
    expenses.addAll({for (final e in page.expenses) e.id: e});
    recurring.addAll({for (final r in page.recurring) r.id: r});
    for (final id in page.removedBudgetIds) {
      removed.add(id);
      budgets.remove(id);
      members.removeWhere((key, _) => key.$1 == id);
      categories.removeWhere((_, c) => c.budgetId == id);
      expenses.removeWhere((_, e) => e.budgetId == id);
      recurring.removeWhere((_, r) => r.budgetId == id);
    }
  }

  void expectSameAs(_Synced full, String reason) {
    expect(profiles, full.profiles, reason: 'profiles, $reason');
    expect(members, full.members, reason: 'members, $reason');
    expect(budgets, full.budgets, reason: 'budgets, $reason');
    expect(categories, full.categories, reason: 'categories, $reason');
    expect(expenses, full.expenses, reason: 'expenses, $reason');
    expect(recurring, full.recurring, reason: 'recurring, $reason');
    expect(removed, full.removed, reason: 'removedBudgetIds, $reason');
  }
}

void main() {
  late AuthHarness api;
  late SharedBudgetFixture fixture;
  late TestUser anna;
  late List<TestUser> crew;

  setUp(() async {
    LogCapture();
    api = await AuthHarness.start();
    fixture = SharedBudgetFixture(api);
    anna = await registerTestUser(api, 'anna', displayName: 'Аня');
    crew = [
      for (final (login, name) in [
        ('vera', 'Вера'),
        ('boris', 'Борис'),
        ('gleb', 'Глеб'),
        ('dasha', 'Даша'),
        ('egor', 'Егор'),
        ('zhenya', 'Женя'),
      ])
        await registerTestUser(api, login, displayName: name),
    ];
  });

  Future<String> sharedBudget(
    String name,
    List<TestUser> users, {
    required int colorShift,
    required int joinedDaysAgo,
  }) async {
    final id = await fixture.budget(ownerId: users.first.id, name: name);
    for (final (i, user) in users.indexed) {
      await fixture.member(
        id,
        user.id,
        role: i == 0 ? MemberRole.owner : MemberRole.member,
        color: CategoryColor
            .values[(i + colorShift) % CategoryColor.values.length],
        joinedDaysAgo: joinedDaysAgo - i,
      );
    }
    return id;
  }

  Future<void> join(String budgetId, TestUser user) => fixture.member(
    budgetId,
    user.id,
    role: MemberRole.member,
    color: CategoryColor.rose,
    joinedDaysAgo: 0,
  );

  Future<void> fill(String budgetId) async {
    final owner = crew.first.id;
    final category = await fixture.category(budgetId, owner);
    await fixture.expense(budgetId, category, owner);
    await fixture.recurring(budgetId, category, owner);
  }

  test('вступление в бюджет с тремя участниками: pull по курсору с limit 1 '
      'и 2 отдаёт тех же участников и профили, что полная загрузка', () async {
    final start = await pullAs(api, anna);
    final trio = crew.take(3).toList();
    final family = await sharedBudget(
      'Семья',
      trio,
      colorShift: 0,
      joinedDaysAgo: 9,
    );
    await join(family, anna);

    final full = await pullAs(api, anna);
    final expected = _Synced.of([full]);
    expect(
      expected.profiles.keys,
      unorderedEquals([for (final u in trio) u.id]),
    );
    expect(
      expected.members.keys.where((key) => key.$1 == family),
      hasLength(4),
    );

    for (final limit in [1, 2]) {
      final pages = await pullUntilDone(
        api,
        anna,
        cursor: start.cursor,
        limit: limit,
      );
      final synced = _Synced.of([start, ...pages.pages]);
      expect(synced.profiles, expected.profiles, reason: 'limit=$limit');
      expect(synced.members, expected.members, reason: 'limit=$limit');
      expect(
        pages.all((p) => p.profiles).map((p) => p.userId),
        unorderedEquals([for (final u in trio) u.id]),
        reason: 'limit=$limit',
      );
    }
  });

  group('страницы pull по курсору в сумме дают полную загрузку при любом '
      'limit, даже когда у многих профилей один seq', () {
    late String dacha;

    Future<void> nothing() async {}

    Future<void> twoBudgets() async {
      dacha = await sharedBudget(
        'Дача',
        [...crew, anna],
        colorShift: 0,
        joinedDaysAgo: 30,
      );
      await fill(dacha);
      final family = await sharedBudget(
        'Семья',
        [...crew, anna],
        colorShift: 5,
        joinedDaysAgo: 20,
      );
      await fill(family);
    }

    Future<void> joinFamily() async {
      final family = await sharedBudget(
        'Семья',
        crew,
        colorShift: 0,
        joinedDaysAgo: 20,
      );
      await fill(family);
      await join(family, anna);
    }

    Future<void> leaveDacha() => api.db.execute(
      'UPDATE budget_members SET left_at = now() '
      r'WHERE budget_id = $1::uuid AND user_id = $2::uuid',
      parameters: [dacha, anna.id],
    );

    Future<void> deleteDacha() => api.db.execute(
      'UPDATE budgets SET deleted_at = now(), updated_at = now(), '
      r'updated_by = $2::uuid WHERE id = $1::uuid',
      parameters: [dacha, crew.first.id],
    );

    for (final (name, before, event) in [
      ('вступление в бюджет', nothing, joinFamily),
      ('выход из бюджета', twoBudgets, leaveDacha),
      ('удаление бюджета', twoBudgets, deleteDacha),
    ]) {
      test(name, () async {
        await before();
        final start = await pullAs(api, anna);
        await event();
        final full = _Synced.of([await pullAs(api, anna)]);

        expect(
          full.profiles.keys,
          unorderedEquals([for (final u in crew) u.id]),
        );
        final startProfiles = _Synced.of([start]).profiles;
        for (final user in crew) {
          expect(
            full.profiles[user.id],
            isNot(startProfiles[user.id]),
            reason: 'событие меняет профиль ${user.login}',
          );
        }

        for (var limit = 1; limit <= 4; limit++) {
          final incremental = await pullUntilDone(
            api,
            anna,
            cursor: start.cursor,
            limit: limit,
          );
          _Synced.of([start, ...incremental.pages])
              .expectSameAs(full, 'по курсору ${start.cursor}, limit=$limit');

          final fromZero = await pullUntilDone(
            api,
            anna,
            limit: limit,
            maxPages: 200,
          );
          _Synced.of(fromZero.pages)
              .expectSameAs(full, 'с курсора 0, limit=$limit');
        }
      });
    }
  });
}
