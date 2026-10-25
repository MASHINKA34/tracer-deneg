import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/auth_support.dart';
import 'support/push_support.dart';
import 'support/shared_budget_support.dart';
import 'support/sync_support.dart';
import 'support/test_support.dart';

void main() {
  late LogCapture logs;
  late AuthHarness api;
  late TestUser anna;
  late String personal;
  late String category;

  setUp(() async {
    logs = LogCapture();
    api = await AuthHarness.start();
    anna = await registerTestUser(api, 'anna');
    personal = await SharedBudgetFixture(api).personalBudgetOf(anna.id);
    category = await firstCategoryOf(api, personal);
  });

  Future<int> delete(SyncEntity entity, String id) async {
    final cursor = (await pullUntilDone(api, anna)).cursor;
    logs.clear();
    final pushed = await pushAs(api, anna, [
      SyncChange.delete(entity: entity, id: id, updatedAt: minutesAgo(1)),
    ]);
    expect(pushed.applied, [id]);
    return cursor;
  }

  group('удаление по одной через push стирает текст, пометка остаётся', () {
    test('трата: комментарий стёрт, сумма, дата и категория остаются, '
        'пометка приходит в pull с пустым комментарием', () async {
      final id = newId();
      await pushAs(api, anna, [
        SyncChange.upsert(
          expenseRecord(
            id: id,
            budgetId: personal,
            categoryId: category,
            authorId: anna.id,
            kopecks: 123400,
            comment: 'Подарок маме на юбилей',
          ),
        ),
      ]);
      final live = (await storedRow(api, 'expenses', id))!;
      expect(live['comment'], 'Подарок маме на юбилей');

      final cursor = await delete(SyncEntity.expense, id);

      final stored = (await storedRow(api, 'expenses', id))!;
      expect(stored.deletedAt, isNotNull);
      expect(stored['comment'], '');
      expect(stored['amount_kopecks'], 123400);
      expect(stored['category_id'], category);
      expect(stored['spent_on'], live['spent_on']);
      expect(stored.seq, greaterThan(live.seq));

      final pulled = await pullUntilDone(api, anna, cursor: cursor);
      final tombstone = pulled.all((p) => p.expenses).single;
      expect(tombstone.id, id);
      expect(tombstone.deletedAt, isNotNull);
      expect(tombstone.comment, '');
      expect(logs.text, isNot(contains('юбилей')));
    });

    test('регулярная трата: название стёрто', () async {
      final id = newId();
      await pushAs(api, anna, [
        SyncChange.upsert(
          recurringRecord(
            id: id,
            budgetId: personal,
            categoryId: category,
            updatedBy: anna.id,
            title: 'Кредит за машину',
          ),
        ),
      ]);

      final cursor = await delete(SyncEntity.recurring, id);

      final stored = (await storedRow(api, 'recurring_rules', id))!;
      expect(stored.deletedAt, isNotNull);
      expect(stored['title'], '');
      expect(stored['amount_kopecks'], 70000);
      final pulled = await pullUntilDone(api, anna, cursor: cursor);
      expect(pulled.all((p) => p.recurring).single.title, '');
    });

    test('категория: название стёрто, эмодзи и цвет остаются', () async {
      final id = newId();
      await pushAs(api, anna, [
        SyncChange.upsert(
          categoryRecord(
            id: id,
            budgetId: personal,
            updatedBy: anna.id,
            name: 'Лекарства',
            emoji: '💊',
          ),
        ),
      ]);

      final cursor = await delete(SyncEntity.category, id);

      final stored = (await storedRow(api, 'categories', id))!;
      expect(stored.deletedAt, isNotNull);
      expect(stored['name'], '');
      expect(stored['emoji'], '💊');
      expect(stored['color'], 'orange');
      final pulled = await pullUntilDone(api, anna, cursor: cursor);
      expect(pulled.all((p) => p.categories).single.name, '');
    });

    test('в логе: какие поля стёрты, без самого текста', () async {
      final id = newId();
      await pushAs(api, anna, [
        SyncChange.upsert(
          expenseRecord(
            id: id,
            budgetId: personal,
            categoryId: category,
            authorId: anna.id,
            comment: 'Секретный комментарий',
          ),
        ),
      ]);

      await delete(SyncEntity.expense, id);

      expect(
        logs.text,
        contains(
          RegExp(
            'DEBUG \\[sync\\] push change applied as tombstone '
            'entity=expense id=$id budgetId=$personal seq=\\d+→\\d+ '
            'storedUpdatedAt=\\S+ deletedAt=\\S+ wiped=comment',
          ),
        ),
      );
      expect(logs.text, isNot(contains('Секретный')));
    });
  });
}
