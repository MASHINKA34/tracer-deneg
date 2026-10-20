import 'package:drift/drift.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import '../current_user.dart';
import '../db/app_database.dart';
import 'outbox_queue.dart';
import 'records.dart';
import 'repository_errors.dart';
import 'repository_writer.dart';

final _log = Logger('repo');

final class BudgetRemoval {
  const BudgetRemoval({
    required this.budgets,
    required this.members,
    required this.categories,
    required this.expenses,
    required this.recurring,
    required this.outbox,
  });

  final int budgets;
  final int members;
  final int categories;
  final int expenses;
  final int recurring;
  final int outbox;

  @override
  String toString() =>
      'BudgetRemoval(budgets=$budgets members=$members '
      'categories=$categories expenses=$expenses recurring=$recurring '
      'outbox=$outbox)';
}

abstract interface class BudgetsRepository {
  Stream<List<Budget>> watchAll();

  Stream<Budget?> watchById(String id);

  Future<Budget> update(String id, {String? name, String? emoji});

  Future<Budget> createLocalPersonal();

  Future<void> applyFromServer(Iterable<Budget> budgets);

  Future<BudgetRemoval> removeBudgetData(Iterable<String> budgetIds);
}

final class DriftBudgetsRepository implements BudgetsRepository {
  DriftBudgetsRepository(
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

  static const String _entity = 'budget';

  static const String personalName = 'Личный бюджет';

  static const String personalEmoji = '👛';

  final AppDatabase _db;
  final RepositoryWriter _writer;

  OutboxQueue get _outbox => _writer.outbox;

  @override
  Stream<List<Budget>> watchAll() => _writer.watch(
    _entity,
    'all',
    (_db.select(_db.budgets)
          ..where((b) => b.deletedAt.isNull())
          ..orderBy([
            (b) => OrderingTerm.asc(b.kind),
            (b) => OrderingTerm.asc(b.createdAt),
            (b) => OrderingTerm.asc(b.id),
          ]))
        .watch()
        .map((rows) => [for (final r in rows) budgetFromRow(r)]),
  );

  @override
  Stream<Budget?> watchById(String id) => _writer.watch(
    _entity,
    'id=$id',
    (_db.select(_db.budgets)
          ..where((b) => b.id.equals(id) & b.deletedAt.isNull()))
        .watchSingleOrNull()
        .map((r) => r == null ? null : budgetFromRow(r)),
  );

  @override
  Future<Budget> update(String id, {String? name, String? emoji}) {
    late int outboxId;
    return _writer.edit(
      _entity,
      'update',
      id: id,
      describe: (b) => 'kind=${b.kind.name} outbox=upsert#$outboxId',
      body: (c) async {
        final row =
            await (_db.select(_db.budgets)
                  ..where((b) => b.id.equals(id) & b.deletedAt.isNull()))
                .getSingleOrNull();
        if (row == null) {
          throw RepositoryException(
            RepositoryFailure.notFound,
            entity: _entity,
            id: id,
          );
        }
        final budget = budgetFromRow(row).copyWith(
          name: name == null ? null : normalizeText(name),
          emoji: emoji == null ? null : normalizeText(emoji),
          updatedAt: c.now,
          updatedBy: c.userId,
        );
        checkValid(validateBudgetName(budget.name), entity: _entity, id: id);
        checkValid(validateEmoji(budget.emoji), entity: _entity, id: id);
        await _db.into(_db.budgets).insertOnConflictUpdate(budgetToRow(budget));
        outboxId = await _outbox.enqueueUpsert(budget);
        return budget;
      },
    );
  }

  @override
  Future<Budget> createLocalPersonal() async {
    final sw = Stopwatch()..start();
    final id = newId();
    var categories = 0;
    var outboxEntries = 0;
    final budget = await _writer.edit(
      _entity,
      'create-personal',
      id: id,
      describe: (b) => b.id == id
          ? 'kind=${b.kind.name} categories=$categories outbox=$outboxEntries'
          : 'skipped existing=${b.id}',
      body: (c) async {
        final existing =
            await (_db.select(_db.budgets)
                  ..where(
                    (b) =>
                        b.kind.equalsValue(BudgetKind.personal) &
                        b.deletedAt.isNull(),
                  )
                  ..orderBy([
                    (b) => OrderingTerm.asc(b.createdAt),
                    (b) => OrderingTerm.asc(b.id),
                  ])
                  ..limit(1))
                .getSingleOrNull();
        if (existing != null) return budgetFromRow(existing);

        final personal = Budget(
          id: id,
          kind: BudgetKind.personal,
          name: personalName,
          emoji: personalEmoji,
          ownerId: c.userId,
          createdAt: c.now,
          updatedAt: c.now,
          updatedBy: c.userId,
        );
        await _db.into(_db.budgets).insert(budgetToRow(personal));
        await _outbox.enqueueUpsert(personal);
        outboxEntries++;
        final presets = buildPresetCategories(
          budgetId: id,
          updatedBy: c.userId,
          now: c.now,
          newId: newId,
        );
        for (final category in presets) {
          await _db.into(_db.categories).insert(categoryToRow(category));
          await _outbox.enqueueUpsert(category);
          categories++;
          outboxEntries++;
        }
        return personal;
      },
    );
    if (budget.id == id) {
      _log.info(
        'personal budget created id=$id categories=$categories '
        'outbox=$outboxEntries in ${sw.elapsedMilliseconds}ms',
      );
    } else {
      _log.fine(
        'personal budget already exists id=${budget.id} '
        'owner=${budget.ownerId}, nothing created '
        'in ${sw.elapsedMilliseconds}ms',
      );
    }
    return budget;
  }

  @override
  Future<void> applyFromServer(Iterable<Budget> budgets) {
    final list = budgets.toList();
    return _writer.sync(
      _entity,
      'apply',
      target: 'count=${list.length}',
      body: () async {
        await _db.batch((b) {
          b.insertAllOnConflictUpdate(_db.budgets, [
            for (final x in list) budgetToRow(x),
          ]);
        });
      },
    );
  }

  @override
  Future<BudgetRemoval> removeBudgetData(Iterable<String> budgetIds) async {
    final ids = budgetIds.toSet().toList();
    final sw = Stopwatch()..start();
    final removal = await _writer.sync(
      _entity,
      'remove-data',
      target: 'budgets=${ids.join(',')}',
      body: () async {
        final expenseIds = _db.selectOnly(_db.expenses)
          ..addColumns([_db.expenses.id])
          ..where(_db.expenses.budgetId.isIn(ids));
        final categoryIds = _db.selectOnly(_db.categories)
          ..addColumns([_db.categories.id])
          ..where(_db.categories.budgetId.isIn(ids));
        final ruleIds = _db.selectOnly(_db.recurringRules)
          ..addColumns([_db.recurringRules.id])
          ..where(_db.recurringRules.budgetId.isIn(ids));
        final outbox =
            await (_db.delete(_db.outbox)..where(
                  (o) =>
                      (o.entity.equalsValue(SyncEntity.budget) &
                          o.entityId.isIn(ids)) |
                      (o.entity.equalsValue(SyncEntity.expense) &
                          o.entityId.isInQuery(expenseIds)) |
                      (o.entity.equalsValue(SyncEntity.category) &
                          o.entityId.isInQuery(categoryIds)) |
                      (o.entity.equalsValue(SyncEntity.recurring) &
                          o.entityId.isInQuery(ruleIds)),
                ))
                .go();
        final expenses = await (_db.delete(
          _db.expenses,
        )..where((e) => e.budgetId.isIn(ids))).go();
        final rules = await (_db.delete(
          _db.recurringRules,
        )..where((r) => r.budgetId.isIn(ids))).go();
        final categories = await (_db.delete(
          _db.categories,
        )..where((c) => c.budgetId.isIn(ids))).go();
        final members = await (_db.delete(
          _db.budgetMembers,
        )..where((m) => m.budgetId.isIn(ids))).go();
        final budgets = await (_db.delete(
          _db.budgets,
        )..where((b) => b.id.isIn(ids))).go();
        return BudgetRemoval(
          budgets: budgets,
          members: members,
          categories: categories,
          expenses: expenses,
          recurring: rules,
          outbox: outbox,
        );
      },
    );
    _log.info(
      'budget data removed ids=${ids.join(',')} budgets=${removal.budgets} '
      'members=${removal.members} categories=${removal.categories} '
      'expenses=${removal.expenses} recurring=${removal.recurring} '
      'outbox=${removal.outbox} in ${sw.elapsedMilliseconds}ms',
    );
    return removal;
  }
}
