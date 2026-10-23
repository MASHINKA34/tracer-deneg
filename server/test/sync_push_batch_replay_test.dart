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
  late String personal;
  late String category;

  setUp(() async {
    logs = LogCapture();
    api = await AuthHarness.start();
    fixture = SharedBudgetFixture(api);
    anna = await registerTestUser(api, 'anna');
    personal = await fixture.personalBudgetOf(anna.id);
    category = await firstCategoryOf(api, personal);
  });

  Expense expense({int kopecks = 64000, DateTime? updatedAt}) => expenseRecord(
    budgetId: personal,
    categoryId: category,
    authorId: anna.id,
    kopecks: kopecks,
    updatedAt: updatedAt,
  );

  group('POST /sync/push: повтор batchId', () {
    test('повтор того же batchId — тот же ответ, изменения не применяются '
        'второй раз', () async {
      final batchId = newId();
      final applied = expense(updatedAt: minutesAgo(20));
      final foreign = expenseRecord(
        budgetId: newId(),
        categoryId: category,
        authorId: anna.id,
      );
      final body = SyncPushRequest(
        batchId: batchId,
        changes: [SyncChange.upsert(applied), SyncChange.upsert(foreign)],
      ).toJson();
      final first = await pushRaw(api, anna, body);
      expect(first.status, 200);
      final stored = (await storedRow(api, 'expenses', applied.id))!;

      final newer = expense(updatedAt: minutesAgo(5), kopecks: 99900);
      await pushAs(api, anna, [
        SyncChange.upsert(
          Expense(
            id: applied.id,
            budgetId: personal,
            categoryId: category,
            amount: Money(55500),
            spentOn: applied.spentOn,
            authorId: anna.id,
            createdAt: applied.createdAt,
            updatedAt: minutesAgo(10),
            updatedBy: anna.id,
          ),
        ),
      ]);
      final edited = (await storedRow(api, 'expenses', applied.id))!;
      expect(edited.seq, greaterThan(stored.seq));

      logs.clear();
      final again = await pushRaw(api, anna, body);
      expect(again.status, 200);
      expect(again.text, first.text);
      final replayed = SyncPushResponse.fromJson(again.json);
      expect(replayed.applied, [applied.id]);
      expect(replayed.rejected, [
        SyncRejection(id: foreign.id, code: ApiErrorCode.notFound.code),
      ]);
      expect(replayed.cursor, stored.seq);
      final after = (await storedRow(api, 'expenses', applied.id))!;
      expect(after.values, edited.values);
      expect(
        logs.text,
        contains(
          'push replay of known batch, nothing applied again '
          'userId=${anna.id} batchId=$batchId changes=2 storedApplied=1 '
          'storedRejected=1 cursor=${stored.seq}',
        ),
      );
      expect(logs.text, isNot(contains('push change applied')));
      expect(logs.text, isNot(contains('push change rejected')));

      final differentBody = await pushRaw(
        api,
        anna,
        SyncPushRequest(
          batchId: batchId,
          changes: [SyncChange.upsert(newer)],
        ).toJson(),
      );
      expect(differentBody.text, first.text);
      expect(await rowCount(api, 'expenses', newer.id), 0);
    });

    test('тот же batchId у другого пользователя — своя пачка', () async {
      final boris = await registerTestUser(api, 'boris');
      final borisPersonal = await fixture.personalBudgetOf(boris.id);
      final borisCategory = await firstCategoryOf(api, borisPersonal);
      final batchId = newId();
      final annaExpense = expense();
      final borisExpense = expenseRecord(
        budgetId: borisPersonal,
        categoryId: borisCategory,
        authorId: boris.id,
      );
      final forAnna = await pushAs(api, anna, [
        SyncChange.upsert(annaExpense),
      ], batchId: batchId);
      final forBoris = await pushAs(api, boris, [
        SyncChange.upsert(borisExpense),
      ], batchId: batchId);
      expect(forAnna.applied, [annaExpense.id]);
      expect(forBoris.applied, [borisExpense.id]);
      expect(await rowCount(api, 'expenses', borisExpense.id), 1);
    });

    test('через 24 часа batchId снова применяется', () async {
      final batchId = newId();
      final first = expense(updatedAt: minutesAgo(30));
      final body = SyncPushRequest(
        batchId: batchId,
        changes: [SyncChange.upsert(first)],
      ).toJson();
      final pushed = SyncPushResponse.fromJson(
        (await pushRaw(api, anna, body)).json,
      );

      await api.db.execute(
        "UPDATE push_batches SET created_at = now() - interval '23 hours 59 "
        r"minutes' WHERE user_id = $1::uuid AND batch_id = $2",
        parameters: [anna.id, batchId],
      );
      final stillReplay = SyncPushResponse.fromJson(
        (await pushRaw(api, anna, body)).json,
      );
      expect(stillReplay.cursor, pushed.cursor);

      await api.db.execute(
        "UPDATE push_batches SET created_at = now() - interval '24 hours 1 "
        r"minute' WHERE user_id = $1::uuid AND batch_id = $2",
        parameters: [anna.id, batchId],
      );
      logs.clear();
      final reapplied = SyncPushResponse.fromJson(
        (await pushRaw(api, anna, body)).json,
      );
      expect(reapplied.applied, [first.id]);
      expect(reapplied.cursor, greaterThan(pushed.cursor));
      expect(logs.text, isNot(contains('push replay')));
      expect(
        await api.count(
          r'SELECT count(*)::int FROM push_batches WHERE user_id = $1::uuid '
          r"AND created_at > now() - interval '1 minute'",
          [anna.id],
        ),
        1,
      );
    });

    test('два одновременных запроса с одним batchId — применяется один раз',
        () async {
      final batchId = newId();
      final body = SyncPushRequest(
        batchId: batchId,
        changes: [
          for (var i = 0; i < 20; i++)
            SyncChange.upsert(expense(kopecks: 1000 + i)),
        ],
      ).toJson();
      final responses = await Future.wait([
        pushRaw(api, anna, body),
        pushRaw(api, anna, body),
        pushRaw(api, anna, body),
      ]);
      for (final response in responses) {
        expect(response.status, 200, reason: response.text);
        expect(response.text, responses.first.text);
      }
      final parsed = SyncPushResponse.fromJson(responses.first.json);
      expect(parsed.applied, hasLength(20));
      expect(
        await api.count(
          r'SELECT max(seq)::int FROM expenses WHERE budget_id = $1::uuid',
          [personal],
        ),
        parsed.cursor,
      );
      expect(
        logs.lines.where((l) => l.contains('push replay of known batch')),
        hasLength(2),
      );
    });
  });
}
