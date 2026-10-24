import 'dart:convert';

import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/auth_support.dart';
import 'support/shared_budget_support.dart';
import 'support/sync_support.dart';
import 'support/test_support.dart';

const _responseKeys = {
  'budgets',
  'members',
  'profiles',
  'categories',
  'expenses',
  'recurring',
  'removedBudgetIds',
  'deletedBudgetIds',
  'cursor',
  'hasMore',
};

void main() {
  late LogCapture logs;
  late AuthHarness api;
  late SharedBudgetFixture fixture;

  setUp(() async {
    logs = LogCapture();
    api = await AuthHarness.start();
    fixture = SharedBudgetFixture(api);
  });

  Future<String> firstCategory(String budgetId) async {
    final rows = await api.db.execute(
      r'SELECT id FROM categories WHERE budget_id = $1::uuid '
      'AND NOT is_system ORDER BY sort_order LIMIT 1',
      parameters: [budgetId],
    );
    return rows.single.first! as String;
  }

  Future<void> insertExpenses(
    String budgetId,
    String categoryId,
    String authorId,
    int count,
  ) => api.db.execute(
    'INSERT INTO expenses (id, budget_id, category_id, amount_kopecks, '
    'spent_on, author_id, created_at, updated_at, updated_by) '
    r'SELECT gen_random_uuid(), $1::uuid, $2::uuid, 100 + n, '
    r"date '2026-10-01' + n % 20, $3::uuid, now(), now(), $3::uuid "
    r'FROM generate_series(1, $4::int) AS n',
    parameters: [budgetId, categoryId, authorId, count],
  );

  Future<int> seqOf(String table, String id) async {
    final rows = await api.db.execute(
      'SELECT seq FROM $table WHERE id = \$1::uuid',
      parameters: [id],
    );
    return rows.single.first! as int;
  }

  group('GET /sync/pull', () {
    test('курсор 0 после регистрации: личный бюджет, участник и 11 '
        'категорий; повтор с курсором — пусто', () async {
      final anna = await registerTestUser(api, 'anna', displayName: 'Аня');
      final personal = await fixture.personalBudgetOf(anna.id);

      final raw = await pullRaw(api, anna, query: 'cursor=0');
      expect(raw.status, 200);
      expect(raw.headers['cache-control'], 'no-store');
      expect(raw.json.keys.toSet(), _responseKeys);
      final full = SyncPullResponse.fromJson(raw.json);

      expect(full.budgets, hasLength(1));
      final budget = full.budgets.single;
      expect(budget.id, personal);
      expect(budget.kind, BudgetKind.personal);
      expect(budget.name, 'Личный бюджет');
      expect(budget.emoji, '👛');
      expect(budget.ownerId, anna.id);
      expect(budget.isDeleted, isFalse);

      expect(full.members, hasLength(1));
      expect(full.members.single.userId, anna.id);
      expect(full.members.single.role, MemberRole.owner);
      expect(full.members.single.isActive, isTrue);

      expect(full.categories, hasLength(11));
      expect(full.categories.map((c) => c.name).toList(), [
        for (final preset in presetCategories) preset.name,
      ]);
      expect(full.categories.where((c) => c.isSystem), hasLength(1));
      expect(full.categories.every((c) => c.budgetId == personal), isTrue);

      expect(full.expenses, isEmpty);
      expect(full.recurring, isEmpty);
      expect(full.profiles, isEmpty);
      expect(full.removedBudgetIds, isEmpty);
      expect(full.hasMore, isFalse);
      expect(full.totalCount, 13);
      final seqs = [budget.seq!, for (final c in full.categories) c.seq!];
      expect(
        full.cursor,
        greaterThanOrEqualTo(seqs.reduce((a, b) => a > b ? a : b)),
      );

      final again = await pullAs(api, anna, cursor: full.cursor);
      expect(again.totalCount, 0);
      expect(again.cursor, full.cursor);
      expect(again.hasMore, isFalse);

      final noParams = await pullRaw(api, anna);
      expect(noParams.status, 200);
      expect(SyncPullResponse.fromJson(noParams.json).totalCount, 13);
    });

    test('501 запись — две страницы: 500 и 1, без потерь и повторов', () async {
      final anna = await registerTestUser(api, 'anna');
      final personal = await fixture.personalBudgetOf(anna.id);
      await insertExpenses(
        personal,
        await firstCategory(personal),
        anna.id,
        488,
      );

      final first = await pullAs(api, anna);
      expect(first.totalCount, pullPageSize);
      expect(first.hasMore, isTrue);

      final second = await pullAs(api, anna, cursor: first.cursor);
      expect(second.totalCount, 1);
      expect(second.hasMore, isFalse);
      expect(second.cursor, greaterThan(first.cursor));
      final secondSeqs = [
        for (final e in second.expenses) e.seq!,
        for (final c in second.categories) c.seq!,
        for (final b in second.budgets) b.seq!,
      ];
      expect(secondSeqs, everyElement(greaterThan(first.cursor)));

      final pages = PulledPages([first, second]);
      final expenseIds = pages.all((p) => p.expenses).map((e) => e.id);
      expect(expenseIds, hasLength(488));
      expect(expenseIds.toSet(), hasLength(488));
      expect(pages.all((p) => p.categories), hasLength(11));
      expect(pages.all((p) => p.budgets), hasLength(1));
      expect(pages.all((p) => p.members), hasLength(1));

      final after = await pullAs(api, anna, cursor: second.cursor);
      expect(after.totalCount, 0);
    });

    test('limit задаёт размер страницы, курсор продолжает с места', () async {
      final anna = await registerTestUser(api, 'anna');
      final personal = await fixture.personalBudgetOf(anna.id);
      await insertExpenses(
        personal,
        await firstCategory(personal),
        anna.id,
        37,
      );

      final pages = await pullUntilDone(api, anna, limit: 10);
      expect(pages.pages.map((p) => p.totalCount), [10, 10, 10, 10, 10]);
      expect(pages.pages.map((p) => p.hasMore), [
        true,
        true,
        true,
        true,
        false,
      ]);
      expect(
        pages.all((p) => p.expenses).map((e) => e.id).toSet(),
        hasLength(37),
      );
      final cursors = pages.pages.map((p) => p.cursor).toList();
      expect(cursors, orderedEquals([...cursors]..sort()));
      expect(cursors.toSet(), hasLength(cursors.length));
    });

    test('надгробия и правки после курсора приходят новыми версиями', () async {
      final anna = await registerTestUser(api, 'anna');
      final personal = await fixture.personalBudgetOf(anna.id);
      final category = await firstCategory(personal);
      final kept = await fixture.expense(personal, category, anna.id);
      final removed = await fixture.expense(personal, category, anna.id);
      final rule = await fixture.recurring(personal, category, anna.id);
      final before = await pullAs(api, anna);
      expect(
        before.expenses.map((e) => e.id),
        unorderedEquals([kept, removed]),
      );
      expect(before.recurring.map((r) => r.id), [rule]);

      for (final (table, id) in [
        ('expenses', removed),
        ('recurring_rules', rule),
        ('categories', category),
      ]) {
        await api.db.execute(
          'UPDATE $table SET deleted_at = now(), updated_at = now() '
          r'WHERE id = $1::uuid',
          parameters: [id],
        );
      }
      await api.db.execute(
        r'UPDATE expenses SET amount_kopecks = 99900 WHERE id = $1::uuid',
        parameters: [kept],
      );

      final changes = await pullAs(api, anna, cursor: before.cursor);
      expect(changes.budgets, isEmpty);
      expect(changes.members, isEmpty);
      expect(changes.categories.map((c) => c.id), [category]);
      expect(changes.categories.single.isDeleted, isTrue);
      expect(changes.recurring.map((r) => r.id), [rule]);
      expect(changes.recurring.single.isDeleted, isTrue);
      final byId = {for (final e in changes.expenses) e.id: e};
      expect(byId.keys, unorderedEquals([kept, removed]));
      expect(byId[removed]!.isDeleted, isTrue);
      expect(byId[kept]!.isDeleted, isFalse);
      expect(byId[kept]!.amount, const Money(99900));
      expect(byId[kept]!.seq, await seqOf('expenses', kept));
      expect(byId[kept]!.seq, greaterThan(before.cursor));
      expect(changes.totalCount, 4);
    });

    test('чужие бюджеты, их участники и траты не попадают', () async {
      final anna = await registerTestUser(api, 'anna');
      final boris = await registerTestUser(api, 'boris', displayName: 'Борис');
      final vera = await registerTestUser(api, 'vera', displayName: 'Вера');
      final borisPersonal = await fixture.personalBudgetOf(boris.id);
      final family = await fixture.budget(ownerId: boris.id);
      await fixture.member(
        family,
        boris.id,
        role: MemberRole.owner,
        color: CategoryColor.green,
        joinedDaysAgo: 5,
      );
      await fixture.member(
        family,
        vera.id,
        role: MemberRole.member,
        color: CategoryColor.orange,
        joinedDaysAgo: 2,
      );
      final category = await fixture.category(family, boris.id);
      final expense = await fixture.expense(family, category, boris.id);
      await fixture.recurring(family, category, vera.id);
      await fixture.expense(
        borisPersonal,
        await firstCategory(borisPersonal),
        boris.id,
      );

      final raw = await pullRaw(api, anna, query: 'cursor=0');
      final page = SyncPullResponse.fromJson(raw.json);
      final annaPersonal = await fixture.personalBudgetOf(anna.id);
      expect(page.budgets.map((b) => b.id), [annaPersonal]);
      expect(page.members.map((m) => m.userId), [anna.id]);
      expect(page.categories.map((c) => c.budgetId).toSet(), {annaPersonal});
      expect(page.expenses, isEmpty);
      expect(page.recurring, isEmpty);
      expect(page.profiles, isEmpty);
      expect(page.removedBudgetIds, isEmpty);
      for (final foreign in [
        family,
        borisPersonal,
        expense,
        boris.id,
        vera.id,
      ]) {
        expect(raw.text, isNot(contains(foreign)), reason: foreign);
      }

      final veraPage = await pullAs(api, vera);
      expect(
        veraPage.budgets.map((b) => b.id),
        unorderedEquals([await fixture.personalBudgetOf(vera.id), family]),
      );
      expect(veraPage.expenses.map((e) => e.id), [expense]);
      expect(veraPage.budgets.map((b) => b.id), isNot(contains(borisPersonal)));
    });

    test('профили участников общих бюджетов: имя, цвет и день рождения; '
        'себя и посторонних нет', () async {
      final anna = await registerTestUser(api, 'anna', displayName: 'Аня');
      final boris = await registerTestUser(api, 'boris', displayName: 'Борис');
      final vera = await registerTestUser(api, 'vera', displayName: 'Вера');
      expect(
        (await api.send(
          'PATCH',
          '/me',
          body: {'birthdayMonth': 6, 'birthdayDay': 12},
          bearer: boris.accessToken,
        )).status,
        200,
      );
      final family = await fixture.budget(ownerId: anna.id);
      await fixture.member(
        family,
        anna.id,
        role: MemberRole.owner,
        color: CategoryColor.green,
        joinedDaysAgo: 9,
      );
      await fixture.member(
        family,
        boris.id,
        role: MemberRole.member,
        color: CategoryColor.orange,
        joinedDaysAgo: 4,
      );
      final friends = await fixture.budget(ownerId: boris.id, name: 'Друзья');
      await fixture.member(
        friends,
        boris.id,
        role: MemberRole.owner,
        color: CategoryColor.purple,
        joinedDaysAgo: 8,
      );
      await fixture.member(
        friends,
        vera.id,
        role: MemberRole.member,
        color: CategoryColor.teal,
        joinedDaysAgo: 1,
      );

      final annaPage = await pullAs(api, anna);
      expect(annaPage.profiles, [
        MemberProfile(
          userId: boris.id,
          displayName: 'Борис',
          avatarColor: CategoryColor.orange,
          birthday: MonthDay(6, 12),
        ),
      ]);
      expect(
        annaPage.members.map((m) => (m.budgetId, m.userId)),
        containsAll([(family, anna.id), (family, boris.id)]),
      );

      final borisPage = await pullAs(api, boris);
      expect(
        {for (final p in borisPage.profiles) p.userId: p.avatarColor},
        {anna.id: CategoryColor.green, vera.id: CategoryColor.teal},
      );
      expect(
        borisPage.profiles.map((p) => p.displayName),
        unorderedEquals(['Аня', 'Вера']),
      );

      final veraPage = await pullAs(api, vera);
      expect(veraPage.profiles.single.userId, boris.id);
      expect(veraPage.profiles.single.avatarColor, CategoryColor.purple);
    });

    test(
      'смена имени и удаление аккаунта участника приходят профилем',
      () async {
        final anna = await registerTestUser(api, 'anna', displayName: 'Аня');
        final boris = await registerTestUser(
          api,
          'boris',
          displayName: 'Борис',
        );
        await api.send(
          'PATCH',
          '/me',
          body: {'birthdayMonth': 3, 'birthdayDay': 8},
          bearer: boris.accessToken,
        );
        final family = await fixture.budget(ownerId: anna.id);
        await fixture.member(
          family,
          anna.id,
          role: MemberRole.owner,
          color: CategoryColor.green,
          joinedDaysAgo: 9,
        );
        await fixture.member(
          family,
          boris.id,
          role: MemberRole.member,
          color: CategoryColor.orange,
          joinedDaysAgo: 4,
        );
        final category = await fixture.category(family, anna.id);
        final borisExpense = await fixture.expense(family, category, boris.id);
        final start = await pullAs(api, anna);
        expect(start.profiles.single.displayName, 'Борис');

        expect(
          (await api.send(
            'PATCH',
            '/me',
            body: {'displayName': 'Боря'},
            bearer: boris.accessToken,
          )).status,
          200,
        );
        final renamed = await pullAs(api, anna, cursor: start.cursor);
        expect(renamed.profiles, [
          MemberProfile(
            userId: boris.id,
            displayName: 'Боря',
            avatarColor: CategoryColor.orange,
            birthday: MonthDay(3, 8),
          ),
        ]);
        expect(renamed.totalCount, 1);

        expect(
          (await api.send(
            'DELETE',
            '/account',
            body: {'password': boris.password},
            bearer: boris.accessToken,
          )).status,
          204,
        );
        final deleted = await pullAs(api, anna, cursor: renamed.cursor);
        expect(deleted.profiles, [
          MemberProfile(
            userId: boris.id,
            displayName: 'Удалённый участник',
            avatarColor: CategoryColor.orange,
          ),
        ]);
        expect(deleted.members.single.userId, boris.id);
        expect(deleted.members.single.isActive, isFalse);
        expect(deleted.expenses, isEmpty);

        final full = await pullAs(api, anna);
        expect(full.profiles.single.displayName, 'Удалённый участник');
        expect(full.expenses.map((e) => e.id), [borisExpense]);
      },
    );

    test(
      'участник и его профиль с одним seq не разрываются страницей',
      () async {
        final anna = await registerTestUser(api, 'anna');
        final boris = await registerTestUser(
          api,
          'boris',
          displayName: 'Борис',
        );
        final family = await fixture.budget(ownerId: anna.id);
        await fixture.member(
          family,
          anna.id,
          role: MemberRole.owner,
          color: CategoryColor.green,
          joinedDaysAgo: 9,
        );
        final category = await fixture.category(family, anna.id);
        final expense = await fixture.expense(family, category, anna.id);
        final start = await pullAs(api, anna);

        await api.db.execute(
          r'UPDATE expenses SET amount_kopecks = 123 WHERE id = $1::uuid',
          parameters: [expense],
        );
        await fixture.member(
          family,
          boris.id,
          role: MemberRole.member,
          color: CategoryColor.orange,
          joinedDaysAgo: 0,
        );

        final byTwo = await pullUntilDone(
          api,
          anna,
          cursor: start.cursor,
          limit: 2,
        );
        expect(byTwo.pages.map((p) => p.totalCount), [1, 2]);
        expect(byTwo.pages.first.expenses.single.id, expense);
        expect(byTwo.pages.last.members.single.userId, boris.id);
        expect(byTwo.pages.last.profiles.single.userId, boris.id);

        final byOne = await pullUntilDone(
          api,
          anna,
          cursor: start.cursor,
          limit: 1,
        );
        expect(byOne.pages.map((p) => p.totalCount), [1, 2]);
        expect(byOne.all((p) => p.profiles).single.userId, boris.id);
        expect(byOne.all((p) => p.members).single.userId, boris.id);
        expect(byOne.cursor, byTwo.cursor);
      },
    );

    test('removedBudgetIds: исключение и удаление общего бюджета', () async {
      final anna = await registerTestUser(api, 'anna');
      final boris = await registerTestUser(api, 'boris', displayName: 'Борис');
      final family = await fixture.budget(ownerId: boris.id);
      final friends = await fixture.budget(ownerId: boris.id, name: 'Друзья');
      for (final budget in [family, friends]) {
        await fixture.member(
          budget,
          boris.id,
          role: MemberRole.owner,
          color: CategoryColor.green,
          joinedDaysAgo: 9,
        );
        await fixture.member(
          budget,
          anna.id,
          role: MemberRole.member,
          color: CategoryColor.orange,
          joinedDaysAgo: 3,
        );
      }
      final familyCategory = await fixture.category(family, boris.id);
      final friendsCategory = await fixture.category(friends, boris.id);
      await fixture.expense(friends, friendsCategory, anna.id);
      final annaStart = await pullAs(api, anna);
      final borisStart = await pullAs(api, boris);
      expect(
        annaStart.budgets.map((b) => b.id),
        containsAll([family, friends]),
      );

      await api.db.execute(
        'UPDATE budget_members SET left_at = now() '
        r'WHERE budget_id = $1::uuid AND user_id = $2::uuid',
        parameters: [family, anna.id],
      );
      final afterExclusion = await fixture.expense(
        family,
        familyCategory,
        boris.id,
      );

      final excluded = await pullAs(api, anna, cursor: annaStart.cursor);
      expect(excluded.removedBudgetIds, [family]);
      expect(excluded.budgets, isEmpty);
      expect(excluded.members, isEmpty);
      expect(excluded.expenses, isEmpty);
      expect(excluded.cursor, greaterThan(annaStart.cursor));
      final repeat = await pullAs(api, anna, cursor: excluded.cursor);
      expect(repeat.removedBudgetIds, isEmpty);
      expect(repeat.totalCount, 0);

      final borisView = await pullAs(api, boris, cursor: borisStart.cursor);
      expect(borisView.removedBudgetIds, isEmpty);
      expect(borisView.members.single.userId, anna.id);
      expect(borisView.members.single.isActive, isFalse);
      expect(borisView.expenses.map((e) => e.id), [afterExclusion]);

      await api.db.execute(
        'UPDATE budgets SET deleted_at = now(), updated_at = now() '
        r'WHERE id = $1::uuid',
        parameters: [friends],
      );
      for (final table in ['categories', 'expenses']) {
        await api.db.execute(
          'UPDATE $table SET deleted_at = now(), updated_at = now() '
          r'WHERE budget_id = $1::uuid',
          parameters: [friends],
        );
      }

      final annaDeleted = await pullAs(api, anna, cursor: repeat.cursor);
      expect(annaDeleted.removedBudgetIds, [friends]);
      expect(annaDeleted.budgets, isEmpty);
      expect(annaDeleted.categories, isEmpty);
      expect(annaDeleted.expenses, isEmpty);
      final borisDeleted = await pullAs(api, boris, cursor: borisView.cursor);
      expect(borisDeleted.removedBudgetIds, [friends]);
      expect(borisDeleted.categories, isEmpty);

      final annaFull = await pullAs(api, anna);
      expect(annaFull.budgets.map((b) => b.id), [
        await fixture.personalBudgetOf(anna.id),
      ]);
      expect(annaFull.removedBudgetIds, unorderedEquals([family, friends]));
      expect(annaFull.profiles, isEmpty);
    });

    test(
      'неверные cursor и limit — 400 bad_request, без токена — 401',
      () async {
        final anna = await registerTestUser(api, 'anna');
        for (final query in [
          'cursor=-1',
          'cursor=abc',
          'cursor=1.5',
          'limit=0',
          'limit=501',
          'limit=x',
        ]) {
          final response = await pullRaw(api, anna, query: query);
          expect(response.status, 400, reason: query);
          expect(
            response.errorCode,
            ApiErrorCode.badRequest.code,
            reason: query,
          );
        }
        expect((await pullRaw(api, anna, query: 'limit=500')).status, 200);
        expect((await pullRaw(api, anna, query: 'limit=1')).status, 200);
        expect(
          logs.text,
          contains(
            'WARN  [sync] pull rejected reason=bad_request userId=${anna.id}',
          ),
        );

        final anonymous = await api.send('GET', '/sync/pull?cursor=0');
        expect(anonymous.status, 401);
        expect(anonymous.errorCode, ApiErrorCode.unauthorized.code);
      },
    );

    test('лог pull: userId, курсор было/стало, сущности по типам, hasMore, '
        'мс и rid; без имён', () async {
      final anna = await registerTestUser(api, 'anna', displayName: 'Аннета');
      logs.clear();
      final page = await pullAs(api, anna);

      final line = logs.lines.singleWhere(
        (l) => l.contains('INFO  [sync] pull userId='),
      );
      expect(
        line,
        matches(
          RegExp(
            'INFO  \\[sync\\] pull userId=${anna.id} '
            'cursor=0→${page.cursor} budgets=1 members=1 profiles=0 '
            'categories=11 expenses=0 recurring=0 removed=0 total=13 '
            r'hasMore=false limit=500 bound=\d+ in \d+ms rid=\S+',
          ),
        ),
      );
      final syncLines = logs.lines
          .where((l) => l.contains('[sync]'))
          .join('\n');
      expect(syncLines, isNot(contains('Аннета')));
      expect(syncLines, isNot(contains('Личный бюджет')));
      expect(jsonEncode(page.toJson()), contains('Личный бюджет'));
    });
  });
}
