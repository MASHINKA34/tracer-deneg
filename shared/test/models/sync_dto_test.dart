import 'dart:convert';

import 'package:shared/shared.dart';
import 'package:test/test.dart';

final at = DateTime.utc(2026, 10, 19, 12);

Map<String, Object?> wire(Map<String, Object?> json) =>
    jsonDecode(jsonEncode(json)) as Map<String, Object?>;

final expense = Expense(
  id: 'e1',
  budgetId: 'b1',
  categoryId: 'c1',
  amount: const Money(14990),
  spentOn: LocalDate(2026, 10, 19),
  authorId: 'u1',
  createdAt: at,
  updatedAt: at,
  updatedBy: 'u1',
);

final budget = Budget(
  id: 'b1',
  kind: BudgetKind.personal,
  name: 'Личный',
  emoji: '👛',
  ownerId: 'u1',
  createdAt: at,
  updatedAt: at,
  updatedBy: 'u1',
);

final category = Category(
  id: 'c1',
  budgetId: 'b1',
  name: 'Кафе',
  emoji: '☕',
  color: CategoryColor.orange,
  sortOrder: 1,
  isSystem: false,
  updatedAt: at,
  updatedBy: 'u1',
);

final rule = RecurringRule(
  id: 'r1',
  budgetId: 'b1',
  categoryId: 'c1',
  title: 'Интернет',
  amount: const Money.rubles(650),
  dayOfMonth: 24,
  startMonth: YearMonth(2026, 10),
  createdAt: at,
  updatedAt: at,
  updatedBy: 'u1',
);

void main() {
  group('SyncChange', () {
    test('upsert: данные записи и обратный разбор', () {
      final change = SyncChange.upsert(expense);
      expect(change.entity, SyncEntity.expense);
      expect(change.op, SyncOp.upsert);
      expect(change.id, 'e1');
      expect(change.updatedAt, at);
      final parsed = SyncChange.fromJson(wire(change.toJson()));
      expect(parsed.decodeRecord(), expense);
      expect(parsed.toString(), 'SyncChange(expense upsert e1)');
    });

    test('decodeRecord для каждой сущности', () {
      for (final SyncRecord record in [budget, category, rule, expense]) {
        final parsed = SyncChange.fromJson(
          wire(SyncChange.upsert(record).toJson()),
        );
        expect(parsed.decodeRecord(), record);
      }
    });

    test('delete без data', () {
      final change = SyncChange.delete(
        entity: SyncEntity.category,
        id: 'c1',
        updatedAt: at,
      );
      expect(change.toJson(), {
        'entity': 'category',
        'op': 'delete',
        'id': 'c1',
        'updatedAt': '2026-10-19T12:00:00.000Z',
      });
      final parsed = SyncChange.fromJson(wire(change.toJson()));
      expect(parsed.op, SyncOp.delete);
      expect(parsed.data, isNull);
      expect(parsed.decodeRecord, throwsStateError);
    });

    test('upsert без data и delete с data — ошибка', () {
      final upsert = wire(SyncChange.upsert(expense).toJson())..remove('data');
      expect(() => SyncChange.fromJson(upsert), throwsFormatException);
      final delete = wire(SyncChange.upsert(expense).toJson())
        ..['op'] = 'delete';
      expect(() => SyncChange.fromJson(delete), throwsFormatException);
    });

    test('id в data должен совпадать с id изменения', () {
      final json = wire(SyncChange.upsert(expense).toJson())..['id'] = 'other';
      expect(
        () => SyncChange.fromJson(json).decodeRecord(),
        throwsFormatException,
      );
    });

    test('неизвестная сущность — ошибка', () {
      final json = wire(SyncChange.upsert(expense).toJson())
        ..['entity'] = 'member';
      expect(() => SyncChange.fromJson(json), throwsFormatException);
    });
  });

  group('push', () {
    test('запрос туда и обратно', () {
      final request = SyncPushRequest(
        batchId: 'batch-1',
        changes: [
          SyncChange.upsert(expense),
          SyncChange.delete(
            entity: SyncEntity.expense,
            id: 'e2',
            updatedAt: at,
          ),
        ],
      );
      final parsed = SyncPushRequest.fromJson(wire(request.toJson()));
      expect(parsed.batchId, 'batch-1');
      expect(parsed.changes, hasLength(2));
      expect(parsed.changes.last.op, SyncOp.delete);
      expect(parsed.toString(), 'SyncPushRequest(batch-1, 2 changes)');
      expect(
        () => request.changes.add(SyncChange.upsert(expense)),
        throwsUnsupportedError,
      );
    });

    test('ответ туда и обратно', () {
      final response = SyncPushResponse(
        applied: ['e1'],
        rejected: [const SyncRejection(id: 'e2', code: 'not_found')],
        cursor: 1234,
      );
      final parsed = SyncPushResponse.fromJson(wire(response.toJson()));
      expect(parsed.applied, ['e1']);
      expect(parsed.rejected, [
        const SyncRejection(id: 'e2', code: 'not_found'),
      ]);
      expect(parsed.cursor, 1234);
      expect(parsed.rejected.single.hashCode, isA<int>());
      expect(parsed.rejected.single.toString(), 'SyncRejection(e2 not_found)');
      expect(parsed.toString(), contains('cursor=1234'));
    });

    test('пачка — до 200 изменений', () {
      expect(maxPushBatchSize, 200);
    });
  });

  group('pull', () {
    test('параметры запроса', () {
      expect(SyncPullQuery().toQueryParameters(), {
        'cursor': '0',
        'limit': '500',
      });
      expect(
        SyncPullQuery.fromQueryParameters({}),
        SyncPullQuery(cursor: 0, limit: 500),
      );
      expect(
        SyncPullQuery.fromQueryParameters({'cursor': '10', 'limit': '100'}),
        SyncPullQuery(cursor: 10, limit: 100),
      );
      expect(
        SyncPullQuery(cursor: 3).hashCode,
        SyncPullQuery(cursor: 3).hashCode,
      );
      expect(
        SyncPullQuery(cursor: 3).toString(),
        'SyncPullQuery(cursor=3 limit=500)',
      );
    });

    test('неверные параметры — ошибка', () {
      for (final query in [
        {'cursor': 'abc'},
        {'cursor': '-1'},
        {'limit': '0'},
        {'limit': '501'},
      ]) {
        expect(
          () => SyncPullQuery.fromQueryParameters(query),
          throwsFormatException,
          reason: '$query',
        );
      }
      expect(() => SyncPullQuery(cursor: -1), throwsArgumentError);
    });

    test('ответ туда и обратно', () {
      final response = SyncPullResponse(
        budgets: [budget],
        members: [
          BudgetMember(
            budgetId: 'b1',
            userId: 'u1',
            role: MemberRole.owner,
            avatarColor: CategoryColor.green,
            joinedAt: at,
          ),
        ],
        profiles: [
          const MemberProfile(
            userId: 'u1',
            displayName: 'Аня',
            avatarColor: CategoryColor.green,
          ),
        ],
        categories: [category],
        expenses: [expense],
        recurring: [rule],
        removedBudgetIds: ['b9'],
        cursor: 77,
        hasMore: true,
      );
      final parsed = SyncPullResponse.fromJson(wire(response.toJson()));
      expect(parsed.budgets, [budget]);
      expect(parsed.members, response.members);
      expect(parsed.profiles, response.profiles);
      expect(parsed.categories, [category]);
      expect(parsed.expenses, [expense]);
      expect(parsed.recurring, [rule]);
      expect(parsed.removedBudgetIds, ['b9']);
      expect(parsed.cursor, 77);
      expect(parsed.hasMore, isTrue);
      expect(parsed.totalCount, 7);
      expect(parsed.toString(), contains('expenses=1'));
    });

    test('пустая страница', () {
      final empty = SyncPullResponse(cursor: 0, hasMore: false);
      final parsed = SyncPullResponse.fromJson(wire(empty.toJson()));
      expect(parsed.totalCount, 0);
      expect(pullPageSize, 500);
    });
  });
}
