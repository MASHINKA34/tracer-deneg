import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart' as pg;
import 'package:shared/shared.dart';

import '../db/database.dart';

final _log = Logger('budgets');

const String _budgetColumns =
    'id, kind, name, emoji, owner_id, created_at, updated_at, updated_by, '
    'deleted_at, seq';

enum BudgetFailureReason {
  notFound,
  forbidden,
  personalBudget,
  inviteNotFound,
  memberNotFound,
  removeSelf,
  idTaken,
}

final class BudgetFailure implements Exception {
  const BudgetFailure(this.reason, this.problem);

  final BudgetFailureReason reason;
  final String problem;

  @override
  String toString() => 'BudgetFailure(${reason.name}: $problem)';
}

final class CreatedBudget {
  const CreatedBudget({required this.budget, required this.replayed});

  final Budget budget;
  final bool replayed;
}

final class _Outcome<T> {
  const _Outcome.ok(T this.value) : reason = null, problem = null;

  const _Outcome.rejected(BudgetFailureReason this.reason, String this.problem)
    : value = null;

  final T? value;
  final BudgetFailureReason? reason;
  final String? problem;
}

class BudgetService {
  BudgetService({required this.db, this._now = DateTime.now});

  final Database db;
  final DateTime Function() _now;

  Future<CreatedBudget> create({
    required String userId,
    required String budgetId,
    required String name,
    required String emoji,
  }) async {
    const action = 'create';
    final sw = Stopwatch()..start();
    final context = {'budgetId': budgetId, 'userId': userId};
    final now = normalizeInstant(_now());
    final categories = buildPresetCategories(
      budgetId: budgetId,
      updatedBy: userId,
      now: now,
      newId: newId,
    );
    final color = CategoryColor.values.first;
    final outcome = await _run<CreatedBudget>(action, context, sw, (tx) async {
      final inserted = await tx.execute(
        'INSERT INTO budgets (id, kind, name, emoji, owner_id, created_at, '
        r"updated_at, updated_by) VALUES ($1::uuid, 'shared', $2, $3, "
        r'$4::uuid, $5::timestamptz, $5::timestamptz, $4::uuid) '
        'ON CONFLICT (id) DO NOTHING RETURNING $_budgetColumns',
        parameters: [
          budgetId,
          normalizeText(name),
          normalizeText(emoji),
          userId,
          now,
        ],
        what: 'insert shared budget',
        logParams: context,
      );
      if (inserted.isEmpty) return _replayCreate(tx, budgetId, userId);
      await tx.execute(
        r'INSERT INTO budget_members (budget_id, user_id, role, avatar_color, '
        r'joined_at) VALUES ($1::uuid, $2::uuid, $3, $4, $5::timestamptz)',
        parameters: [budgetId, userId, MemberRole.owner.name, color.name, now],
        what: 'insert shared budget owner',
        logParams: {...context, 'avatarColor': color.name},
      );
      for (final category in categories) {
        await tx.execute(
          r'INSERT INTO categories (id, budget_id, name, emoji, color, '
          r'sort_order, is_system, updated_at, updated_by) VALUES ($1::uuid, '
          r'$2::uuid, $3, $4, $5, $6, $7, $8::timestamptz, $9::uuid)',
          parameters: [
            category.id,
            budgetId,
            category.name,
            category.emoji,
            category.color?.name,
            category.sortOrder,
            category.isSystem,
            now,
            userId,
          ],
          what: 'insert preset category',
          logParams: {
            'budgetId': budgetId,
            'categoryId': category.id,
            'sortOrder': category.sortOrder,
          },
        );
      }
      return _Outcome.ok(
        CreatedBudget(budget: _budgetFromRow(inserted.single), replayed: false),
      );
    });
    final created = _unwrap(action, outcome, context, sw);
    if (created.replayed) {
      _log.info(
        'budget $action replayed: already created by this user, '
        'nothing written budgetId=$budgetId userId=$userId '
        'seq=${created.budget.seq} in ${sw.elapsedMilliseconds}ms',
      );
    } else {
      _log.info(
        'budget $action ok budgetId=$budgetId userId=$userId kind=shared '
        'role=${MemberRole.owner.name} avatarColor=${color.name} '
        'categories=${categories.length} seq=${created.budget.seq} '
        'in ${sw.elapsedMilliseconds}ms',
      );
    }
    return created;
  }

  Future<_Outcome<CreatedBudget>> _replayCreate(
    DbSession tx,
    String budgetId,
    String userId,
  ) async {
    final context = {'budgetId': budgetId, 'userId': userId};
    final rows = await tx.execute(
      'SELECT $_budgetColumns FROM budgets WHERE id = \$1::uuid FOR UPDATE',
      parameters: [budgetId],
      what: 'lock budget with taken id',
      logParams: context,
    );
    if (rows.isEmpty) {
      return const _Outcome.rejected(
        BudgetFailureReason.idTaken,
        'budget id was taken and released concurrently',
      );
    }
    final budget = _budgetFromRow(rows.single);
    final member = await tx.execute(
      r'SELECT role FROM budget_members WHERE budget_id = $1::uuid '
      r'AND user_id = $2::uuid AND left_at IS NULL',
      parameters: [budgetId, userId],
      what: 'membership of user in budget with taken id',
      logParams: context,
    );
    final isOwner =
        member.isNotEmpty && member.single[0] == MemberRole.owner.name;
    if (budget.kind == BudgetKind.shared &&
        budget.ownerId == userId &&
        !budget.isDeleted &&
        isOwner) {
      _log.fine(
        'budget id already taken by the same owner, treating as retry '
        '${formatContext(context)} seq=${budget.seq}',
      );
      return _Outcome.ok(CreatedBudget(budget: budget, replayed: true));
    }
    return _Outcome.rejected(
      BudgetFailureReason.idTaken,
      'id belongs to another budget kind=${budget.kind.name} '
      'sameOwner=${budget.ownerId == userId} deleted=${budget.isDeleted} '
      'activeOwner=$isOwner',
    );
  }

  Future<_Outcome<T>> _run<T>(
    String action,
    Map<String, Object?> context,
    Stopwatch sw,
    Future<_Outcome<T>> Function(DbSession tx) body,
  ) async {
    try {
      return await db.transaction('budget $action', body);
    } catch (e) {
      _log.warning(
        'budget $action failed ${formatContext(context)} '
        'in ${sw.elapsedMilliseconds}ms: ${describeError(e)}',
      );
      rethrow;
    }
  }

  T _unwrap<T>(
    String action,
    _Outcome<T> outcome,
    Map<String, Object?> context,
    Stopwatch sw,
  ) {
    final reason = outcome.reason;
    if (reason == null) return outcome.value as T;
    _reject(action, reason, outcome.problem!, context, sw);
  }

  Never _reject(
    String action,
    BudgetFailureReason reason,
    String problem,
    Map<String, Object?> context,
    Stopwatch sw,
  ) {
    final byRights = switch (reason) {
      BudgetFailureReason.notFound ||
      BudgetFailureReason.forbidden ||
      BudgetFailureReason.personalBudget => ' by rights',
      _ => '',
    };
    _log.warning(
      'budget $action rejected$byRights reason=${_reasonCode(reason)} '
      '${formatContext(context)} ${formatContext({'problem': problem})} '
      'in ${sw.elapsedMilliseconds}ms',
    );
    throw BudgetFailure(reason, problem);
  }
}

String _reasonCode(BudgetFailureReason reason) => switch (reason) {
  BudgetFailureReason.notFound ||
  BudgetFailureReason.memberNotFound => ApiErrorCode.notFound.code,
  BudgetFailureReason.forbidden ||
  BudgetFailureReason.personalBudget => ApiErrorCode.forbidden.code,
  BudgetFailureReason.inviteNotFound => ApiErrorCode.inviteNotFound.code,
  BudgetFailureReason.removeSelf => ApiErrorCode.badRequest.code,
  BudgetFailureReason.idTaken => ApiErrorCode.conflict.code,
};

Budget _budgetFromRow(pg.ResultRow row) => Budget(
  id: row[0]! as String,
  kind: BudgetKind.values.byName(row[1]! as String),
  name: row[2]! as String,
  emoji: row[3]! as String,
  ownerId: row[4]! as String,
  createdAt: row[5]! as DateTime,
  updatedAt: row[6]! as DateTime,
  updatedBy: row[7]! as String,
  deletedAt: row[8] as DateTime?,
  seq: row[9]! as int,
);
