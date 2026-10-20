import 'package:drift/drift.dart';
import 'package:shared/shared.dart';

import '../current_user.dart';
import '../db/app_database.dart';
import 'outbox_queue.dart';
import 'records.dart';
import 'repository_errors.dart';
import 'repository_writer.dart';

final class CategoryDeletion {
  const CategoryDeletion({
    required this.category,
    required this.otherCategoryId,
    required this.movedExpenses,
    required this.movedRecurring,
  });

  final Category category;
  final String otherCategoryId;
  final int movedExpenses;
  final int movedRecurring;

  @override
  String toString() =>
      'CategoryDeletion(${category.id} → $otherCategoryId '
      'expenses=$movedExpenses recurring=$movedRecurring)';
}

abstract interface class CategoriesRepository {
  Stream<List<Category>> watchByBudget(String budgetId);

  Stream<Category?> watchById(String id);

  Future<Category> create({
    required String budgetId,
    required String name,
    required String emoji,
    required CategoryColor color,
  });

  Future<Category> update(
    String id, {
    String? name,
    String? emoji,
    CategoryColor? color,
  });

  Future<CategoryDeletion> delete(String id);

  Future<void> applyFromServer(Iterable<Category> categories);
}

final class DriftCategoriesRepository implements CategoriesRepository {
  DriftCategoriesRepository(
    this._db, {
    required CurrentUser currentUser,
    required OutboxQueue outbox,
    Now now = DateTime.now,
  }) : _writer = RepositoryWriter(
         _db,
         outbox: outbox,
         currentUser: currentUser,
         now: now,
       );

  static const String _entity = 'category';

  final AppDatabase _db;
  final RepositoryWriter _writer;

  OutboxQueue get _outbox => _writer.outbox;

  @override
  Stream<List<Category>> watchByBudget(String budgetId) => _writer.watch(
    _entity,
    'budget=$budgetId',
    (_db.select(_db.categories)
          ..where((c) => c.budgetId.equals(budgetId) & c.deletedAt.isNull())
          ..orderBy([
            (c) => OrderingTerm.asc(c.isSystem),
            (c) => OrderingTerm.asc(c.sortOrder),
            (c) => OrderingTerm.asc(c.id),
          ]))
        .watch()
        .map((rows) => [for (final r in rows) categoryFromRow(r)]),
  );

  @override
  Stream<Category?> watchById(String id) => _writer.watch(
    _entity,
    'id=$id',
    (_db.select(_db.categories)
          ..where((c) => c.id.equals(id) & c.deletedAt.isNull()))
        .watchSingleOrNull()
        .map((r) => r == null ? null : categoryFromRow(r)),
  );

  Future<Category> _live(String id) async {
    final row = await (_db.select(
      _db.categories,
    )..where((c) => c.id.equals(id) & c.deletedAt.isNull())).getSingleOrNull();
    if (row == null) {
      throw RepositoryException(
        RepositoryFailure.notFound,
        entity: _entity,
        id: id,
      );
    }
    return categoryFromRow(row);
  }

  void _rejectSystem(Category c) {
    if (c.isSystem) {
      throw RepositoryException(
        RepositoryFailure.systemCategory,
        entity: _entity,
        id: c.id,
      );
    }
  }

  void _validate(Category c) {
    checkValid(validateCategoryName(c.name), entity: _entity, id: c.id);
    checkValid(validateEmoji(c.emoji), entity: _entity, id: c.id);
  }

  @override
  Future<Category> create({
    required String budgetId,
    required String name,
    required String emoji,
    required CategoryColor color,
  }) {
    final id = newId();
    late int outboxId;
    return _writer.edit(
      _entity,
      'create',
      id: id,
      describe: (c) =>
          'budget=${c.budgetId} order=${c.sortOrder} outbox=upsert#$outboxId',
      body: (c) async {
        final draft = Category(
          id: id,
          budgetId: budgetId,
          name: normalizeText(name),
          emoji: normalizeText(emoji),
          color: color,
          sortOrder: 0,
          isSystem: false,
          updatedAt: c.now,
          updatedBy: c.userId,
        );
        _validate(draft);
        final existing = await (_db.select(
          _db.categories,
        )..where((t) => t.budgetId.equals(budgetId))).get();
        final category = draft.copyWith(
          sortOrder: nextCategorySortOrder([
            for (final r in existing) categoryFromRow(r),
          ]),
        );
        await _db.into(_db.categories).insert(categoryToRow(category));
        outboxId = await _outbox.enqueueUpsert(category);
        return category;
      },
    );
  }

  @override
  Future<Category> update(
    String id, {
    String? name,
    String? emoji,
    CategoryColor? color,
  }) {
    late int outboxId;
    return _writer.edit(
      _entity,
      'update',
      id: id,
      describe: (c) => 'budget=${c.budgetId} outbox=upsert#$outboxId',
      body: (c) async {
        final current = await _live(id);
        _rejectSystem(current);
        final category = current.copyWith(
          name: name == null ? null : normalizeText(name),
          emoji: emoji == null ? null : normalizeText(emoji),
          color: color ?? current.color,
          updatedAt: c.now,
          updatedBy: c.userId,
        );
        _validate(category);
        await _db
            .into(_db.categories)
            .insertOnConflictUpdate(categoryToRow(category));
        outboxId = await _outbox.enqueueUpsert(category);
        return category;
      },
    );
  }

  @override
  Future<CategoryDeletion> delete(String id) => _writer.edit(
    _entity,
    'delete',
    id: id,
    describe: (d) =>
        'budget=${d.category.budgetId} other=${d.otherCategoryId} '
        'movedExpenses=${d.movedExpenses} movedRecurring=${d.movedRecurring} '
        'outbox=${d.movedExpenses + d.movedRecurring + 1}',
    body: (c) async {
      final current = await _live(id);
      _rejectSystem(current);
      final other =
          await (_db.select(_db.categories)
                ..where(
                  (t) =>
                      t.budgetId.equals(current.budgetId) &
                      t.isSystem.equals(true) &
                      t.deletedAt.isNull(),
                )
                ..orderBy([(t) => OrderingTerm.asc(t.id)])
                ..limit(1))
              .getSingleOrNull();
      if (other == null) {
        throw RepositoryException(
          RepositoryFailure.otherCategoryMissing,
          entity: _entity,
          id: id,
        );
      }

      final expenses = await (_db.select(
        _db.expenses,
      )..where((e) => e.categoryId.equals(id) & e.deletedAt.isNull())).get();
      for (final row in expenses) {
        final moved = expenseFromRow(
          row,
        ).copyWith(categoryId: other.id, updatedAt: c.now, updatedBy: c.userId);
        await _db
            .into(_db.expenses)
            .insertOnConflictUpdate(expenseToRow(moved));
        await _outbox.enqueueUpsert(moved);
      }

      final rules = await (_db.select(
        _db.recurringRules,
      )..where((r) => r.categoryId.equals(id) & r.deletedAt.isNull())).get();
      for (final row in rules) {
        final moved = recurringFromRow(
          row,
        ).copyWith(categoryId: other.id, updatedAt: c.now, updatedBy: c.userId);
        await _db
            .into(_db.recurringRules)
            .insertOnConflictUpdate(recurringToRow(moved));
        await _outbox.enqueueUpsert(moved);
      }

      final tombstone = current.copyWith(
        deletedAt: c.now,
        updatedAt: c.now,
        updatedBy: c.userId,
      );
      await _db
          .into(_db.categories)
          .insertOnConflictUpdate(categoryToRow(tombstone));
      await _outbox.enqueueDelete(SyncEntity.category, id, at: c.now);
      return CategoryDeletion(
        category: tombstone,
        otherCategoryId: other.id,
        movedExpenses: expenses.length,
        movedRecurring: rules.length,
      );
    },
  );

  @override
  Future<void> applyFromServer(Iterable<Category> categories) {
    final list = categories.toList();
    return _writer.sync(
      _entity,
      'apply',
      target: 'count=${list.length}',
      body: () async {
        await _db.batch((b) {
          b.insertAllOnConflictUpdate(_db.categories, [
            for (final c in list) categoryToRow(c),
          ]);
        });
      },
    );
  }
}
