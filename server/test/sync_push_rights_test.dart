import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/auth_support.dart';
import 'support/push_support.dart';
import 'support/shared_budget_support.dart';
import 'support/test_support.dart';

void main() {
  late LogCapture logs;
  late AuthHarness api;
  late SharedBudgetFixture fixture;
  late TestUser anna;
  late TestUser boris;
  late String annaPersonal;
  late String annaCategory;
  late String borisPersonal;
  late String borisCategory;

  setUp(() async {
    logs = LogCapture();
    api = await AuthHarness.start();
    fixture = SharedBudgetFixture(api);
    anna = await registerTestUser(api, 'anna');
    boris = await registerTestUser(api, 'boris');
    annaPersonal = await fixture.personalBudgetOf(anna.id);
    borisPersonal = await fixture.personalBudgetOf(boris.id);
    annaCategory = await firstCategoryOf(api, annaPersonal);
    borisCategory = await firstCategoryOf(api, borisPersonal);
  });

  String rightsLine(String entity, String op, String id) =>
      'push change rejected by rights reason=not_found '
      'entity=$entity op=$op id=$id';

  group('POST /sync/push: права', () {
    test('трата в чужом бюджете — rejected not_found, ничего не записано, '
        'warn с сущностью и id', () async {
      final expense = expenseRecord(
        budgetId: annaPersonal,
        categoryId: annaCategory,
        authorId: boris.id,
      );
      final response = await pushAs(api, boris, [SyncChange.upsert(expense)]);
      expect(response.applied, isEmpty);
      expect(response.rejected, [
        SyncRejection(id: expense.id, code: ApiErrorCode.notFound.code),
      ]);
      expect(response.cursor, 0);
      expect(await rowCount(api, 'expenses', expense.id), 0);
      final line = logs.lines.singleWhere(
        (l) => l.contains(rightsLine('expense', 'upsert', expense.id)),
      );
      expect(line, contains(' WARN  [sync] '));
      expect(line, contains('problem="not a member of target budget"'));
      expect(line, contains('budgetId=$annaPersonal'));
      expect(line, contains('userId=${boris.id}'));
    });

    test('правка и удаление чужой траты по известному id — not_found, '
        'трата не меняется', () async {
      final expenseId = await fixture.expense(
        annaPersonal,
        annaCategory,
        anna.id,
      );
      final before = (await storedRow(api, 'expenses', expenseId))!;
      final edit = expenseRecord(
        id: expenseId,
        budgetId: borisPersonal,
        categoryId: borisCategory,
        authorId: boris.id,
        updatedAt: DateTime.now().toUtc(),
      );
      final response = await pushAs(api, boris, [
        SyncChange.upsert(edit),
        SyncChange.delete(
          entity: SyncEntity.expense,
          id: expenseId,
          updatedAt: DateTime.now().toUtc(),
        ),
      ]);
      expect(response.applied, isEmpty);
      expect(response.rejected, [
        SyncRejection(id: expenseId, code: ApiErrorCode.notFound.code),
        SyncRejection(id: expenseId, code: ApiErrorCode.notFound.code),
      ]);
      expect(response.cursor, 0);
      final after = (await storedRow(api, 'expenses', expenseId))!;
      expect(after.values, before.values);
      expect(
        logs.text,
        contains(rightsLine('expense', 'delete', expenseId)),
      );
      expect(logs.text, contains('problem="not a member of record budget"'));
    });

    test('удаление несуществующей записи — тот же not_found, что и чужой',
        () async {
      final id = newId();
      final response = await pushAs(api, anna, [
        SyncChange.delete(
          entity: SyncEntity.category,
          id: id,
          updatedAt: DateTime.now().toUtc(),
        ),
      ]);
      expect(response.rejected, [
        SyncRejection(id: id, code: ApiErrorCode.notFound.code),
      ]);
      expect(logs.text, contains(rightsLine('category', 'delete', id)));
      expect(logs.text, contains('problem="record not found"'));
    });

    test('перенос своей траты в чужой бюджет — not_found, трата на месте',
        () async {
      final expense = expenseRecord(
        budgetId: annaPersonal,
        categoryId: annaCategory,
        authorId: anna.id,
        updatedAt: minutesAgo(20),
      );
      await pushAs(api, anna, [SyncChange.upsert(expense)]);
      final moved = expense.copyWith(
        budgetId: borisPersonal,
        categoryId: borisCategory,
        updatedAt: minutesAgo(5),
      );
      final response = await pushAs(api, anna, [SyncChange.upsert(moved)]);
      expect(response.rejected, [
        SyncRejection(id: expense.id, code: ApiErrorCode.notFound.code),
      ]);
      final stored = (await storedRow(api, 'expenses', expense.id))!;
      expect(stored.budgetId, annaPersonal);
      expect(response.cursor, stored.seq);
    });

    test('исключённый участник общего бюджета не пишет в него', () async {
      final family = await fixture.budget(ownerId: anna.id);
      await fixture.member(
        family,
        anna.id,
        role: MemberRole.owner,
        color: CategoryColor.green,
        joinedDaysAgo: 10,
      );
      await fixture.member(
        family,
        boris.id,
        role: MemberRole.member,
        color: CategoryColor.orange,
        joinedDaysAgo: 5,
      );
      final familyCategory = await fixture.category(family, anna.id);
      final first = expenseRecord(
        budgetId: family,
        categoryId: familyCategory,
        authorId: boris.id,
      );
      expect((await pushAs(api, boris, [SyncChange.upsert(first)])).applied, [
        first.id,
      ]);

      await api.db.execute(
        r'UPDATE budget_members SET left_at = now() '
        r'WHERE budget_id = $1::uuid AND user_id = $2::uuid',
        parameters: [family, boris.id],
      );
      final second = expenseRecord(
        budgetId: family,
        categoryId: familyCategory,
        authorId: boris.id,
      );
      final response = await pushAs(api, boris, [SyncChange.upsert(second)]);
      expect(response.rejected, [
        SyncRejection(id: second.id, code: ApiErrorCode.notFound.code),
      ]);
      expect(await rowCount(api, 'expenses', second.id), 0);
    });

    test('участник общего бюджета правит чужую трату в нём; автор и время '
        'создания остаются, updatedBy — кто прислал', () async {
      final family = await fixture.budget(ownerId: anna.id);
      await fixture.member(
        family,
        anna.id,
        role: MemberRole.owner,
        color: CategoryColor.green,
        joinedDaysAgo: 10,
      );
      await fixture.member(
        family,
        boris.id,
        role: MemberRole.member,
        color: CategoryColor.orange,
        joinedDaysAgo: 5,
      );
      final familyCategory = await fixture.category(family, anna.id);
      final created = minutesAgo(60);
      final expense = expenseRecord(
        budgetId: family,
        categoryId: familyCategory,
        authorId: anna.id,
        createdAt: created,
        updatedAt: minutesAgo(30),
      );
      await pushAs(api, anna, [SyncChange.upsert(expense)]);
      final edited = Expense(
        id: expense.id,
        budgetId: family,
        categoryId: familyCategory,
        amount: Money(12345),
        spentOn: LocalDate(2026, 10, 21),
        authorId: boris.id,
        createdAt: minutesAgo(1),
        updatedAt: minutesAgo(1),
        updatedBy: anna.id,
      );
      final response = await pushAs(api, boris, [SyncChange.upsert(edited)]);
      expect(response.applied, [expense.id]);
      final stored = (await storedRow(api, 'expenses', expense.id))!;
      expect(stored['amount_kopecks'], 12345);
      expect(stored['author_id'], anna.id);
      expect(stored['created_at'], created);
      expect(stored.updatedBy, boris.id);
    });
  });

  group('POST /sync/push: категория траты — из того же бюджета', () {
    test('трата и регулярная с категорией другого своего бюджета — '
        'validation_failed, ничего не записано', () async {
      final family = await fixture.budget(ownerId: anna.id);
      await fixture.member(
        family,
        anna.id,
        role: MemberRole.owner,
        color: CategoryColor.green,
        joinedDaysAgo: 3,
      );
      final familyCategory = await fixture.category(family, anna.id);
      final expense = expenseRecord(
        budgetId: annaPersonal,
        categoryId: familyCategory,
        authorId: anna.id,
      );
      final rule = recurringRecord(
        budgetId: family,
        categoryId: annaCategory,
        updatedBy: anna.id,
      );
      final missing = expenseRecord(
        budgetId: annaPersonal,
        categoryId: newId(),
        authorId: anna.id,
      );
      final response = await pushAs(api, anna, [
        SyncChange.upsert(expense),
        SyncChange.upsert(rule),
        SyncChange.upsert(missing),
      ]);
      expect(response.applied, isEmpty);
      expect(response.rejected, [
        SyncRejection(id: expense.id, code: ApiErrorCode.validationFailed.code),
        SyncRejection(id: rule.id, code: ApiErrorCode.validationFailed.code),
        SyncRejection(id: missing.id, code: ApiErrorCode.validationFailed.code),
      ]);
      expect(await rowCount(api, 'expenses', expense.id), 0);
      expect(await rowCount(api, 'recurring_rules', rule.id), 0);
      expect(await rowCount(api, 'expenses', missing.id), 0);
      expect(logs.text, contains('is in another budget'));
      expect(logs.text, contains('not found'));
    });

    test('после отказа удаление аккаунта проходит: личные данные не '
        'ссылаются на категории общего бюджета', () async {
      final family = await fixture.budget(ownerId: boris.id);
      await fixture.member(
        family,
        boris.id,
        role: MemberRole.owner,
        color: CategoryColor.green,
        joinedDaysAgo: 3,
      );
      await fixture.member(
        family,
        anna.id,
        role: MemberRole.member,
        color: CategoryColor.orange,
        joinedDaysAgo: 2,
      );
      final crossed = expenseRecord(
        budgetId: family,
        categoryId: annaCategory,
        authorId: anna.id,
      );
      final response = await pushAs(api, anna, [SyncChange.upsert(crossed)]);
      expect(response.rejected.single.code, ApiErrorCode.validationFailed.code);

      final deleted = await api.send(
        'DELETE',
        '/account',
        body: {'password': anna.password},
        bearer: anna.accessToken,
      );
      expect(deleted.status, 204);
    });

    test('категория не переезжает в другой бюджет', () async {
      final category = categoryRecord(
        budgetId: annaPersonal,
        updatedBy: anna.id,
        updatedAt: minutesAgo(20),
      );
      await pushAs(api, anna, [SyncChange.upsert(category)]);
      final family = await fixture.budget(ownerId: anna.id);
      await fixture.member(
        family,
        anna.id,
        role: MemberRole.owner,
        color: CategoryColor.green,
        joinedDaysAgo: 3,
      );
      final moved = Category(
        id: category.id,
        budgetId: family,
        name: category.name,
        emoji: category.emoji,
        color: category.color,
        sortOrder: category.sortOrder,
        isSystem: false,
        updatedAt: minutesAgo(5),
        updatedBy: anna.id,
      );
      final response = await pushAs(api, anna, [SyncChange.upsert(moved)]);
      expect(response.rejected, [
        SyncRejection(
          id: category.id,
          code: ApiErrorCode.validationFailed.code,
        ),
      ]);
      expect(
        (await storedRow(api, 'categories', category.id))!.budgetId,
        annaPersonal,
      );
    });
  });

  group('POST /sync/push: бюджеты и системная категория', () {
    test('переименование своего бюджета принимается, тип и владелец '
        'не меняются', () async {
      final rows = await api.db.execute(
        'SELECT id, kind, name, emoji, owner_id, created_at, updated_at, '
        r'updated_by FROM budgets WHERE id = $1::uuid',
        parameters: [annaPersonal],
      );
      final row = rows.single;
      final renamed = Budget(
        id: annaPersonal,
        kind: BudgetKind.shared,
        name: '  Мои деньги  ',
        emoji: '💰',
        ownerId: boris.id,
        createdAt: row[5]! as DateTime,
        updatedAt: DateTime.now().toUtc(),
        updatedBy: anna.id,
      );
      final response = await pushAs(api, anna, [SyncChange.upsert(renamed)]);
      expect(response.applied, [annaPersonal]);
      final stored = (await storedRow(api, 'budgets', annaPersonal))!;
      expect(stored['name'], 'Мои деньги');
      expect(stored['emoji'], '💰');
      expect(stored['kind'], 'personal');
      expect(stored['owner_id'], anna.id);
    });

    test('новый бюджет через push — not_found, удаление бюджета — '
        'forbidden', () async {
      final now = DateTime.now().toUtc();
      final created = Budget(
        id: newId(),
        kind: BudgetKind.shared,
        name: 'Отпуск',
        emoji: '🏖',
        ownerId: anna.id,
        createdAt: now,
        updatedAt: now,
        updatedBy: anna.id,
      );
      final response = await pushAs(api, anna, [
        SyncChange.upsert(created),
        SyncChange.delete(
          entity: SyncEntity.budget,
          id: annaPersonal,
          updatedAt: now,
        ),
      ]);
      expect(response.rejected, [
        SyncRejection(id: created.id, code: ApiErrorCode.notFound.code),
        SyncRejection(id: annaPersonal, code: ApiErrorCode.forbidden.code),
      ]);
      expect(await rowCount(api, 'budgets', created.id), 0);
      expect(
        (await storedRow(api, 'budgets', annaPersonal))!.deletedAt,
        isNull,
      );
      expect(
        logs.text,
        contains(
          'push change rejected by rights reason=forbidden entity=budget '
          'op=delete id=$annaPersonal',
        ),
      );
    });

    test('системную «Другое» удалить нельзя, новую системную создать '
        'нельзя', () async {
      final other = await systemCategoryOf(api, annaPersonal);
      final fake = categoryRecord(
        budgetId: annaPersonal,
        updatedBy: anna.id,
        name: 'Другое 2',
        color: null,
        isSystem: true,
      );
      final response = await pushAs(api, anna, [
        SyncChange.delete(
          entity: SyncEntity.category,
          id: other,
          updatedAt: DateTime.now().toUtc(),
        ),
        SyncChange.upsert(fake),
      ]);
      expect(response.rejected, [
        SyncRejection(id: other, code: ApiErrorCode.validationFailed.code),
        SyncRejection(id: fake.id, code: ApiErrorCode.validationFailed.code),
      ]);
      expect((await storedRow(api, 'categories', other))!.deletedAt, isNull);
      expect(await rowCount(api, 'categories', fake.id), 0);
    });
  });
}
