import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:milionchik/data/db/app_database.dart';
import 'package:milionchik/data/db/converters.dart';
import 'package:shared/shared.dart';

void main() {
  group('конвертеры без базы', () {
    test('LocalDate ↔ YYYY-MM-DD', () {
      const c = LocalDateConverter();
      expect(c.toSql(LocalDate(2026, 3, 7)), '2026-03-07');
      expect(c.fromSql('2026-03-07'), LocalDate(2026, 3, 7));
      final date = LocalDate(2024, 2, 29);
      expect(c.fromSql(c.toSql(date)), date);
      expect(() => c.fromSql('2026-02-30'), throwsFormatException);
    });

    test('YearMonth ↔ YYYY-MM', () {
      const c = YearMonthConverter();
      expect(c.toSql(YearMonth(2026, 1)), '2026-01');
      expect(c.fromSql('2026-12'), YearMonth(2026, 12));
      expect(() => c.fromSql('2026-13'), throwsFormatException);
    });

    test('момент ↔ ISO-8601 UTC с миллисекундами', () {
      const c = InstantConverter();
      final moscow = DateTime.parse('2026-10-19T18:40:12.345678+03:00');
      expect(c.toSql(moscow), '2026-10-19T15:40:12.345Z');
      final back = c.fromSql(c.toSql(moscow));
      expect(back.isUtc, isTrue);
      expect(back, DateTime.utc(2026, 10, 19, 15, 40, 12, 345));
      final local = DateTime(2026, 1, 1, 0, 0, 0, 1);
      expect(
        c.fromSql(c.toSql(local)).millisecondsSinceEpoch,
        local.millisecondsSinceEpoch,
      );
      expect(() => c.fromSql('2026-10-19T15:40:12'), throwsFormatException);
    });
  });

  group('через базу', () {
    late AppDatabase db;

    setUp(() => db = AppDatabase.memory());
    tearDown(() => db.close());

    final createdAt = DateTime.parse('2026-10-19T18:40:12.345+03:00');
    final updatedAt = DateTime.utc(2026, 10, 20, 7, 5, 9, 1);

    ExpensesCompanion expense(String id, LocalDate spentOn) =>
        ExpensesCompanion.insert(
          id: id,
          budgetId: 'b1',
          categoryId: 'c1',
          amountKopecks: 64000,
          spentOn: spentOn,
          comment: '',
          commentSearch: '',
          authorId: 'u1',
          recurringMonth: Value(YearMonth(2026, 10)),
          createdAt: createdAt,
          updatedAt: updatedAt,
          updatedBy: 'u1',
        );

    test('трата: дата, месяц и моменты туда-обратно', () async {
      await db.into(db.expenses).insert(expense('e1', LocalDate(2026, 10, 9)));

      final row = await db.select(db.expenses).getSingle();
      expect(row.spentOn, LocalDate(2026, 10, 9));
      expect(row.recurringMonth, YearMonth(2026, 10));
      expect(row.createdAt, DateTime.utc(2026, 10, 19, 15, 40, 12, 345));
      expect(row.createdAt.isUtc, isTrue);
      expect(row.updatedAt, updatedAt);
      expect(row.deletedAt, isNull);
      expect(row.serverSeq, isNull);

      final raw = await db
          .customSelect(
            'SELECT spent_on, recurring_month, created_at, updated_at '
            'FROM expenses',
          )
          .getSingle();
      expect(raw.read<String>('spent_on'), '2026-10-09');
      expect(raw.read<String>('recurring_month'), '2026-10');
      expect(raw.read<String>('created_at'), '2026-10-19T15:40:12.345Z');
      expect(raw.read<String>('updated_at'), '2026-10-20T07:05:09.001Z');
    });

    test('надгробие и пустой месяц регулярной', () async {
      final deletedAt = DateTime.utc(2026, 10, 21, 12);
      await db
          .into(db.expenses)
          .insert(
            expense('e1', LocalDate(2026, 10, 9)).copyWith(
              recurringMonth: const Value(null),
              deletedAt: Value(deletedAt),
              serverSeq: const Value(42),
            ),
          );
      final row = await db.select(db.expenses).getSingle();
      expect(row.recurringMonth, isNull);
      expect(row.deletedAt, deletedAt);
      expect(row.serverSeq, 42);
    });

    test('дата текстом сортируется как дата', () async {
      for (final (id, date) in [
        ('a', LocalDate(2026, 10, 10)),
        ('b', LocalDate(2026, 9, 30)),
        ('c', LocalDate(2026, 10, 1)),
        ('d', LocalDate(2025, 12, 31)),
      ]) {
        await db.into(db.expenses).insert(expense(id, date));
      }
      final rows = await (db.select(
        db.expenses,
      )..orderBy([(e) => OrderingTerm.asc(e.spentOn)])).get();
      expect(rows.map((r) => r.id), ['d', 'b', 'c', 'a']);
    });

    test('регулярная: месяц начала', () async {
      await db
          .into(db.recurringRules)
          .insert(
            RecurringRulesCompanion.insert(
              id: 'r1',
              budgetId: 'b1',
              categoryId: 'c1',
              title: 't',
              amountKopecks: 99900,
              dayOfMonth: 31,
              startMonth: YearMonth(2026, 2),
              createdAt: createdAt,
              updatedAt: updatedAt,
              updatedBy: 'u1',
            ),
          );
      final row = await db.select(db.recurringRules).getSingle();
      expect(row.startMonth, YearMonth(2026, 2));
      expect(row.createdAt, DateTime.utc(2026, 10, 19, 15, 40, 12, 345));
    });

    test('перечисления хранятся по имени', () async {
      await db
          .into(db.budgets)
          .insert(
            BudgetsCompanion.insert(
              id: 'b1',
              kind: BudgetKind.shared,
              name: 'n',
              emoji: 'e',
              ownerId: 'u1',
              createdAt: createdAt,
              updatedAt: updatedAt,
              updatedBy: 'u1',
            ),
          );
      await db
          .into(db.categories)
          .insert(
            CategoriesCompanion.insert(
              id: 'c1',
              budgetId: 'b1',
              name: 'n',
              nameSearch: 'n',
              emoji: 'e',
              color: const Value(CategoryColor.teal),
              sortOrder: 9,
              isSystem: false,
              updatedAt: updatedAt,
              updatedBy: 'u1',
            ),
          );
      final budget = await db.select(db.budgets).getSingle();
      expect(budget.kind, BudgetKind.shared);
      final category = await db.select(db.categories).getSingle();
      expect(category.color, CategoryColor.teal);
      final raw = await db
          .customSelect('SELECT b.kind, c.color FROM budgets b, categories c')
          .getSingle();
      expect(raw.read<String>('kind'), 'shared');
      expect(raw.read<String>('color'), 'teal');
    });
  });
}
