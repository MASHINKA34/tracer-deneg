import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/auth_support.dart';
import 'support/push_support.dart';
import 'support/shared_budget_support.dart';
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

  Expense expense({
    required String id,
    required DateTime updatedAt,
    int kopecks = 64000,
  }) => expenseRecord(
    id: id,
    budgetId: personal,
    categoryId: category,
    authorId: anna.id,
    kopecks: kopecks,
    updatedAt: updatedAt,
  );

  group('POST /sync/push: последняя правка побеждает', () {
    test('младшая правка не затирает старшую, равная по времени '
        'принимается', () async {
      final id = newId();
      final created = await pushAs(api, anna, [
        SyncChange.upsert(expense(id: id, updatedAt: minutesAgo(30))),
      ]);
      expect(created.applied, [id]);
      final newer = minutesAgo(10);
      await pushAs(api, anna, [
        SyncChange.upsert(expense(id: id, updatedAt: newer, kopecks: 90000)),
      ]);
      final before = (await storedRow(api, 'expenses', id))!;
      expect(before['amount_kopecks'], 90000);

      logs.clear();
      final stale = await pushAs(api, anna, [
        SyncChange.upsert(
          expense(id: id, updatedAt: minutesAgo(20), kopecks: 11100),
        ),
      ]);
      expect(stale.applied, isEmpty);
      expect(stale.rejected, [
        SyncRejection(id: id, code: ApiErrorCode.conflict.code),
      ]);
      expect(stale.cursor, before.seq);
      final after = (await storedRow(api, 'expenses', id))!;
      expect(after['amount_kopecks'], 90000);
      expect(after.updatedAt, newer);
      expect(after.seq, before.seq);
      expect(
        logs.text,
        contains(
          'push change rejected reason=conflict entity=expense op=upsert '
          'id=$id problem="older than stored version, last edit wins"',
        ),
      );

      final same = await pushAs(api, anna, [
        SyncChange.upsert(expense(id: id, updatedAt: newer, kopecks: 12300)),
      ]);
      expect(same.applied, [id]);
      final tied = (await storedRow(api, 'expenses', id))!;
      expect(tied['amount_kopecks'], 12300);
      expect(tied.seq, greaterThan(after.seq));
      expect(same.cursor, tied.seq);
    });

    test('updatedAt позже сервера больше чем на 5 минут обрезается до '
        'серверного времени, в пределах 5 минут — как есть', () async {
      final id = newId();
      final future = normalizeInstant(
        DateTime.now().toUtc().add(const Duration(days: 1)),
      );
      final before = DateTime.now().toUtc();
      final pushed = await pushAs(api, anna, [
        SyncChange.upsert(expense(id: id, updatedAt: future)),
      ]);
      final after = DateTime.now().toUtc();
      expect(pushed.applied, [id]);
      final clamped = (await storedRow(api, 'expenses', id))!.updatedAt;
      expect(
        clamped.isBefore(before.subtract(const Duration(seconds: 1))),
        isFalse,
      );
      expect(clamped.isAfter(after), isFalse);
      expect(
        logs.text,
        contains(
          'push change updatedAt is in the future, clamped to server time '
          'entity=expense op=upsert id=$id incoming=${encodeInstant(future)}',
        ),
      );

      final soon = normalizeInstant(
        DateTime.now().toUtc().add(const Duration(minutes: 4)),
      );
      final edit = await pushAs(api, anna, [
        SyncChange.upsert(expense(id: id, updatedAt: soon, kopecks: 77700)),
      ]);
      expect(edit.applied, [id]);
      final stored = (await storedRow(api, 'expenses', id))!;
      expect(stored.updatedAt, soon);
      expect(stored['amount_kopecks'], 77700);
    });

    test('удаление из будущего тоже обрезается', () async {
      final id = newId();
      await pushAs(api, anna, [
        SyncChange.upsert(expense(id: id, updatedAt: minutesAgo(5))),
      ]);
      final before = DateTime.now().toUtc();
      final deleted = await pushAs(api, anna, [
        SyncChange.delete(
          entity: SyncEntity.expense,
          id: id,
          updatedAt: DateTime.now().toUtc().add(const Duration(hours: 3)),
        ),
      ]);
      final after = DateTime.now().toUtc();
      expect(deleted.applied, [id]);
      final stored = (await storedRow(api, 'expenses', id))!;
      expect(
        stored.deletedAt!.isBefore(before.subtract(const Duration(seconds: 1))),
        isFalse,
      );
      expect(stored.deletedAt!.isAfter(after), isFalse);
    });
  });

  group('POST /sync/push: надгробие побеждает правку', () {
    test('удаление старше последней правки всё равно удаляет, правка после '
        'удаления отклоняется, запись остаётся удалённой', () async {
      final id = newId();
      final edited = minutesAgo(5);
      await pushAs(api, anna, [
        SyncChange.upsert(expense(id: id, updatedAt: minutesAgo(30))),
      ]);
      await pushAs(api, anna, [
        SyncChange.upsert(expense(id: id, updatedAt: edited, kopecks: 50000)),
      ]);
      final live = (await storedRow(api, 'expenses', id))!;

      final deletedAt = minutesAgo(20);
      final deleted = await pushAs(api, anna, [
        SyncChange.delete(
          entity: SyncEntity.expense,
          id: id,
          updatedAt: deletedAt,
        ),
      ]);
      expect(deleted.applied, [id]);
      expect(deleted.rejected, isEmpty);
      final tombstone = (await storedRow(api, 'expenses', id))!;
      expect(tombstone.deletedAt, deletedAt);
      expect(tombstone.updatedAt, edited);
      expect(tombstone.updatedBy, anna.id);
      expect(tombstone['amount_kopecks'], 50000);
      expect(tombstone.seq, greaterThan(live.seq));
      expect(deleted.cursor, tombstone.seq);

      logs.clear();
      final revived = await pushAs(api, anna, [
        SyncChange.upsert(
          expense(id: id, updatedAt: DateTime.now().toUtc(), kopecks: 99900),
        ),
      ]);
      expect(revived.applied, isEmpty);
      expect(revived.rejected, [
        SyncRejection(id: id, code: ApiErrorCode.conflict.code),
      ]);
      expect(revived.cursor, tombstone.seq);
      final still = (await storedRow(api, 'expenses', id))!;
      expect(still.deletedAt, deletedAt);
      expect(still['amount_kopecks'], 50000);
      expect(still.seq, tombstone.seq);
      expect(
        logs.text,
        contains('problem="record is deleted, tombstone wins over edit"'),
      );
    });

    test(
      'повторное удаление принимается без новой записи и нового seq',
      () async {
        final id = newId();
        await pushAs(api, anna, [
          SyncChange.upsert(expense(id: id, updatedAt: minutesAgo(30))),
        ]);
        final first = await pushAs(api, anna, [
          SyncChange.delete(
            entity: SyncEntity.expense,
            id: id,
            updatedAt: minutesAgo(20),
          ),
        ]);
        final tombstone = (await storedRow(api, 'expenses', id))!;
        final again = await pushAs(api, anna, [
          SyncChange.delete(
            entity: SyncEntity.expense,
            id: id,
            updatedAt: minutesAgo(1),
          ),
        ]);
        expect(again.applied, [id]);
        expect(again.cursor, first.cursor);
        final stored = (await storedRow(api, 'expenses', id))!;
        expect(stored.seq, tombstone.seq);
        expect(stored.deletedAt, tombstone.deletedAt);
      },
    );

    test('правка и удаление одной траты в одной пачке — удалена', () async {
      final id = newId();
      final deletedAt = minutesAgo(2);
      final pushed = await pushAs(api, anna, [
        SyncChange.upsert(expense(id: id, updatedAt: minutesAgo(3))),
        SyncChange.delete(
          entity: SyncEntity.expense,
          id: id,
          updatedAt: deletedAt,
        ),
      ]);
      expect(pushed.applied, [id, id]);
      final stored = (await storedRow(api, 'expenses', id))!;
      expect(stored.deletedAt, deletedAt);
    });
  });
}
