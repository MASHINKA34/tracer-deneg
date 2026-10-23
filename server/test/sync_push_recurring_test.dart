import 'dart:async';

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
  late String family;
  late String category;
  late RecurringRule rule;
  final october = YearMonth(2026, 10);

  setUp(() async {
    logs = LogCapture();
    api = await AuthHarness.start();
    fixture = SharedBudgetFixture(api);
    anna = await registerTestUser(api, 'anna');
    boris = await registerTestUser(api, 'boris');
    family = await fixture.budget(ownerId: anna.id);
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
    category = await fixture.category(family, anna.id);
    rule = recurringRecord(
      budgetId: family,
      categoryId: category,
      updatedBy: anna.id,
      updatedAt: minutesAgo(120),
    );
    final created = await pushAs(api, anna, [SyncChange.upsert(rule)]);
    expect(created.applied, [rule.id]);
  });

  Expense generated(TestUser by, DateTime at) => expenseRecord(
    id: recurringExpenseId(rule.id, october),
    budgetId: family,
    categoryId: category,
    authorId: by.id,
    kopecks: rule.amount.kopecks,
    spentOn: chargeDate(rule.dayOfMonth, october),
    comment: rule.title,
    recurringId: rule.id,
    recurringMonth: october,
    updatedAt: at,
  );

  Future<int> chargesOfRule() => api.count(
    r'SELECT count(*)::int FROM expenses WHERE recurring_id = $1::uuid '
    r"AND recurring_month = '2026-10'",
    [rule.id],
  );

  group('POST /sync/push: траты регулярных', () {
    test('два телефона создали одну и ту же трату регулярной — на сервере '
        'одна, автор — первый', () async {
      final fromAnna = generated(anna, minutesAgo(30));
      final fromBoris = generated(boris, minutesAgo(20));
      expect(fromAnna.id, fromBoris.id);

      final first = await pushAs(api, anna, [SyncChange.upsert(fromAnna)]);
      final second = await pushAs(api, boris, [SyncChange.upsert(fromBoris)]);
      expect(first.applied, [fromAnna.id]);
      expect(second.applied, [fromBoris.id]);
      expect(second.cursor, greaterThan(first.cursor));
      expect(await chargesOfRule(), 1);
      final stored = (await storedRow(api, 'expenses', fromAnna.id))!;
      expect(stored['author_id'], anna.id);
      expect(stored.updatedBy, boris.id);
      expect(stored['recurring_month'], '2026-10');
    });

    test(
      'удалённая трата регулярной не пересоздаётся вторым телефоном',
      () async {
        final fromAnna = generated(anna, minutesAgo(30));
        await pushAs(api, anna, [SyncChange.upsert(fromAnna)]);
        await pushAs(api, anna, [
          SyncChange.delete(
            entity: SyncEntity.expense,
            id: fromAnna.id,
            updatedAt: minutesAgo(25),
          ),
        ]);
        final fromBoris = generated(boris, minutesAgo(1));
        final response = await pushAs(api, boris, [
          SyncChange.upsert(fromBoris),
        ]);
        expect(response.rejected, [
          SyncRejection(id: fromBoris.id, code: ApiErrorCode.conflict.code),
        ]);
        expect(await chargesOfRule(), 1);
        expect(
          (await storedRow(api, 'expenses', fromAnna.id))!.deletedAt,
          isNotNull,
        );
      },
    );

    test('вставка той же траты параллельной транзакцией: push ждёт её, '
        'правит запись и не падает', () async {
      final id = recurringExpenseId(rule.id, october);
      final release = Completer<void>();
      final inserted = Completer<void>();
      final writer = api.db.withConnection(
        'parallel recurring writer',
        (connection) => connection.transaction('parallel insert', (tx) async {
          await tx.execute(
            'INSERT INTO expenses (id, budget_id, category_id, '
            'amount_kopecks, spent_on, author_id, recurring_id, '
            'recurring_month, created_at, updated_at, updated_by) VALUES '
            r"($1::uuid, $2::uuid, $3::uuid, 70000, '2026-10-05', $4::uuid, "
            r"$5::uuid, '2026-10', now() - interval '1 hour', "
            r"now() - interval '1 hour', $4::uuid)",
            parameters: [id, family, category, anna.id, rule.id],
          );
          inserted.complete();
          await release.future;
        }),
      );
      await inserted.future;

      final pushing = pushAs(api, boris, [
        SyncChange.upsert(generated(boris, minutesAgo(1))),
      ]);
      await waitUntil(() => logs.text.contains('query insert expenses row'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
      release.complete();
      await writer;
      final response = await pushing;

      expect(response.applied, [id]);
      expect(await chargesOfRule(), 1);
      final stored = (await storedRow(api, 'expenses', id))!;
      expect(stored['author_id'], anna.id);
      expect(stored.updatedBy, boris.id);
      expect(
        logs.text,
        contains(
          'push change lost insert race to a concurrent writer, '
          'retrying as update entity=expense id=$id',
        ),
      );
    });
  });
}
