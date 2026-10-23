import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/auth_support.dart';
import 'support/push_support.dart';
import 'support/shared_budget_support.dart';
import 'support/sync_support.dart';
import 'support/test_support.dart';

const _secretComment = 'секретная заметка про подарок';
const _secretKopecks = 87654321;

void main() {
  late LogCapture logs;
  late RecordingNotifier notifier;
  late AuthHarness api;
  late TestUser phone;
  late TestUser tablet;
  late String personal;

  setUp(() async {
    logs = LogCapture();
    notifier = RecordingNotifier();
    api = await AuthHarness.start(notifier: notifier);
    phone = await registerTestUser(api, 'anna');
    final login = await api.login(deviceName: 'Galaxy Tab');
    expect(login.status, 200);
    tablet = TestUser(
      id: phone.id,
      login: phone.login,
      password: phone.password,
      accessToken: login.json['accessToken']! as String,
      refreshToken: login.json['refreshToken']! as String,
    );
    personal = await SharedBudgetFixture(api).personalBudgetOf(phone.id);
  });

  group('POST /sync/push → GET /sync/pull', () {
    test('трата с телефона видна планшету после pull; трата раньше своей '
        'новой категории в пачке — обе применены', () async {
      final initial = await pullUntilDone(api, tablet);

      final category = categoryRecord(
        budgetId: personal,
        updatedBy: phone.id,
        updatedAt: minutesAgo(3),
      );
      final expense = expenseRecord(
        budgetId: personal,
        categoryId: category.id,
        authorId: phone.id,
        kopecks: _secretKopecks,
        comment: _secretComment,
        updatedAt: minutesAgo(2),
      );
      final batchId = newId();
      final body = SyncPushRequest(
        batchId: batchId,
        changes: [SyncChange.upsert(expense), SyncChange.upsert(category)],
      ).toJson();
      final pushed = await pushRaw(api, phone, body);
      expect(pushed.status, 200);
      expect(pushed.headers['cache-control'], 'no-store');
      final response = SyncPushResponse.fromJson(pushed.json);
      expect(response.applied, [expense.id, category.id]);
      expect(response.rejected, isEmpty);

      final pulled = await pullUntilDone(api, tablet, cursor: initial.cursor);
      final expenses = pulled.all((p) => p.expenses);
      final categories = pulled.all((p) => p.categories);
      expect(categories.map((c) => c.id), [category.id]);
      expect(expenses, hasLength(1));
      final seen = expenses.single;
      expect(seen.id, expense.id);
      expect(seen.amount, Money(_secretKopecks));
      expect(seen.comment, _secretComment);
      expect(seen.categoryId, category.id);
      expect(seen.updatedAt, expense.updatedAt);
      expect(seen.authorId, phone.id);
      expect(seen.seq, response.cursor);
      expect(pulled.cursor, greaterThanOrEqualTo(response.cursor));

      final again = await pushRaw(api, phone, body);
      expect(again.text, pushed.text);

      expect(
        logs.text,
        contains(
          'push userId=${phone.id} batchId=$batchId changes=2 applied=2 '
          'rejected=0 codes=- writes=2 budgets=[$personal] '
          'cursor=${response.cursor}',
        ),
      );
      expect(logs.text, isNot(contains(_secretComment)));
      expect(logs.text, isNot(contains('$_secretKopecks')));
    });

    test('событие для WebSocket — после фиксации, только если что-то '
        'записано', () async {
      final category = await firstCategoryOf(api, personal);
      final expense = expenseRecord(
        budgetId: personal,
        categoryId: category,
        authorId: phone.id,
      );
      final batchId = newId();
      final response = await pushAs(api, phone, [
        SyncChange.upsert(expense),
      ], batchId: batchId);
      expect(notifier.events, hasLength(1));
      final event = notifier.events.single;
      expect(event.reason, 'push');
      expect(event.userId, phone.id);
      expect(event.budgetIds, {personal});
      expect(event.cursor, response.cursor);

      await pushAs(api, phone, [SyncChange.upsert(expense)], batchId: batchId);
      await pushAs(api, phone, [
        SyncChange.upsert(
          expenseRecord(
            budgetId: newId(),
            categoryId: category,
            authorId: phone.id,
          ),
        ),
      ]);
      expect(notifier.events, hasLength(1));
    });
  });

  group('POST /sync/push: ошибка базы посреди пачки', () {
    test('500, пачка откатывается целиком, batchId не занят, в логе нет '
        'комментария и суммы; повтор после исправления применяется', () async {
      await api.db.execute(
        'CREATE FUNCTION push_test_fail() RETURNS trigger LANGUAGE plpgsql '
        r'AS $$ BEGIN IF NEW.amount_kopecks = 87654321 THEN '
        "RAISE EXCEPTION 'new row violates check constraint' USING "
        "ERRCODE = '23514', DETAIL = format('Failing row contains (%s, %s).', "
        r'NEW.comment, NEW.amount_kopecks); END IF; RETURN NEW; END $$',
      );
      await api.db.execute(
        'CREATE TRIGGER push_test_fail BEFORE INSERT ON expenses '
        'FOR EACH ROW EXECUTE FUNCTION push_test_fail()',
      );
      final category = categoryRecord(budgetId: personal, updatedBy: phone.id);
      final expense = expenseRecord(
        budgetId: personal,
        categoryId: category.id,
        authorId: phone.id,
        kopecks: _secretKopecks,
        comment: _secretComment,
      );
      final body = SyncPushRequest(
        batchId: newId(),
        changes: [SyncChange.upsert(category), SyncChange.upsert(expense)],
      ).toJson();

      final failed = await pushRaw(api, phone, body);
      expect(failed.status, 500);
      expect(await rowCount(api, 'categories', category.id), 0);
      expect(
        await api.count(
          r'SELECT count(*)::int FROM push_batches WHERE user_id = $1::uuid',
          [phone.id],
        ),
        0,
      );
      expect(notifier.events, isEmpty);
      expect(logs.text, contains('push failed userId=${phone.id}'));
      expect(
        logs.text,
        contains('sqlState=23514 detail="Failing row contains (…)."'),
      );
      expect(logs.text, isNot(contains(_secretComment)));
      expect(logs.text, isNot(contains('$_secretKopecks')));

      await api.db.execute('DROP TRIGGER push_test_fail ON expenses');
      final retried = await pushRaw(api, phone, body);
      expect(retried.status, 200);
      expect(SyncPushResponse.fromJson(retried.json).applied, [
        category.id,
        expense.id,
      ]);
    });
  });
}
