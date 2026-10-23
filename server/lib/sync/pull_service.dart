import 'dart:math';

import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart' as pg;
import 'package:shared/shared.dart';

import '../db/database.dart';

final _log = Logger('sync');

enum _Kind { budget, member, profile, category, expense, recurring, removed }

class _Item {
  const _Item(this.kind, this.seq, this.value);

  final _Kind kind;
  final int seq;
  final Object value;
}

const String _activeBudgets =
    'WITH active AS (SELECT m.budget_id AS id FROM budget_members m '
    'JOIN budgets b ON b.id = m.budget_id '
    r'WHERE m.user_id = $1::uuid AND m.left_at IS NULL '
    'AND b.deleted_at IS NULL) ';

const String _range =
    r'seq > $2::bigint AND seq <= $3::bigint ORDER BY seq '
    r'FETCH FIRST ($4::int) ROWS WITH TIES';

const String _budgetsSql =
    '${_activeBudgets}SELECT id, kind, name, emoji, owner_id, created_at, '
    'updated_at, updated_by, deleted_at, seq FROM budgets '
    'WHERE id IN (SELECT id FROM active) AND $_range';

const String _membersSql =
    '${_activeBudgets}SELECT budget_id, user_id, role, avatar_color, '
    'joined_at, left_at, seq FROM budget_members '
    'WHERE budget_id IN (SELECT id FROM active) AND $_range';

const String _categoriesSql =
    '${_activeBudgets}SELECT id, budget_id, name, emoji, color, sort_order, '
    'is_system, updated_at, updated_by, deleted_at, seq FROM categories '
    'WHERE budget_id IN (SELECT id FROM active) AND $_range';

const String _expensesSql =
    '${_activeBudgets}SELECT id, budget_id, category_id, amount_kopecks, '
    'spent_on::text, comment, author_id, recurring_id, recurring_month, '
    'created_at, updated_at, updated_by, deleted_at, seq FROM expenses '
    'WHERE budget_id IN (SELECT id FROM active) AND $_range';

const String _recurringSql =
    '${_activeBudgets}SELECT id, budget_id, category_id, title, '
    'amount_kopecks, day_of_month, start_month, created_at, updated_at, '
    'updated_by, deleted_at, seq FROM recurring_rules '
    'WHERE budget_id IN (SELECT id FROM active) AND $_range';

const String _profilesSql =
    'WITH shared_budgets AS (SELECT m.budget_id AS id FROM budget_members m '
    'JOIN budgets b ON b.id = m.budget_id '
    r'WHERE m.user_id = $1::uuid AND m.left_at IS NULL '
    "AND b.deleted_at IS NULL AND b.kind = 'shared'), "
    'links AS (SELECT x.user_id, x.avatar_color, '
    'row_number() OVER (PARTITION BY x.user_id '
    'ORDER BY x.left_at IS NOT NULL, x.joined_at, x.budget_id) AS rank '
    'FROM budget_members x JOIN users u ON u.id = x.user_id '
    'WHERE x.budget_id IN (SELECT id FROM shared_budgets) '
    r'AND x.user_id <> $1::uuid '
    'AND (x.left_at IS NULL OR u.deleted_at IS NOT NULL)), '
    'touched AS (SELECT o.user_id, greatest(max(o.seq), max(me.seq), '
    'max(b.seq) FILTER (WHERE b.deleted_at IS NOT NULL)) AS seq '
    'FROM budget_members o JOIN budget_members me '
    r'ON me.budget_id = o.budget_id AND me.user_id = $1::uuid '
    'JOIN budgets b ON b.id = o.budget_id '
    r'WHERE o.user_id <> $1::uuid GROUP BY o.user_id), '
    'profiles AS (SELECT u.id, u.display_name, u.birthday_month, '
    'u.birthday_day, '
    'max(l.avatar_color) FILTER (WHERE l.rank = 1) AS avatar_color, '
    'greatest(u.seq, max(t.seq)) AS seq '
    'FROM users u JOIN links l ON l.user_id = u.id '
    'JOIN touched t ON t.user_id = u.id GROUP BY u.id) '
    'SELECT id, display_name, birthday_month, birthday_day, avatar_color, seq '
    'FROM profiles WHERE $_range';

const String _removedSql =
    'WITH removed AS (SELECT b.id, greatest('
    r'CASE WHEN m.left_at IS NOT NULL AND m.seq > $2::bigint '
    r'AND m.seq <= $3::bigint THEN m.seq END, '
    r'CASE WHEN b.deleted_at IS NOT NULL AND b.seq > $2::bigint '
    r'AND b.seq <= $3::bigint THEN b.seq END) AS seq '
    'FROM budget_members m JOIN budgets b ON b.id = m.budget_id '
    r'WHERE m.user_id = $1::uuid '
    'AND (m.left_at IS NOT NULL OR b.deleted_at IS NOT NULL)) '
    'SELECT id, seq FROM removed WHERE $_range';

const String _lockNotAvailable = '55P03';

class PullService {
  PullService({
    required this.db,
    this.barrierTimeout = const Duration(seconds: 2),
  });

  final Database db;
  final Duration barrierTimeout;
  int _safeBound = 0;

  Future<SyncPullResponse> pull({
    required String userId,
    required SyncPullQuery query,
  }) async {
    final sw = Stopwatch()..start();
    final context = {
      'userId': userId,
      'cursor': query.cursor,
      'limit': query.limit,
    };
    try {
      final bound = await _upperBound(context);
      final read = bound <= query.cursor
          ? (items: <_Item>[], filled: <_Kind>{})
          : await _read(userId, query, bound, context);
      final page = _cut(read.items, query.limit, filled: read.filled);
      final response = _response(page.items, query.cursor, page.hasMore);
      _log.fine(
        'pull page cut on seq boundary fetched=${read.items.length} '
        'kept=${page.items.length} fetchSize=${query.limit + 1} '
        'queriesAtFetchSize=[${read.filled.map((k) => k.name).join(',')}] '
        'hasMore=${page.hasMore} ${formatContext(context)}',
      );
      _log.info(
        'pull userId=$userId cursor=${query.cursor}→${response.cursor} '
        'budgets=${response.budgets.length} '
        'members=${response.members.length} '
        'profiles=${response.profiles.length} '
        'categories=${response.categories.length} '
        'expenses=${response.expenses.length} '
        'recurring=${response.recurring.length} '
        'removed=${response.removedBudgetIds.length} '
        'total=${response.totalCount} hasMore=${response.hasMore} '
        'limit=${query.limit} bound=$bound in ${sw.elapsedMilliseconds}ms',
      );
      return response;
    } catch (e) {
      _log.warning(
        'pull failed ${formatContext(context)} '
        'in ${sw.elapsedMilliseconds}ms: ${describeError(e)}',
      );
      rethrow;
    }
  }

  Future<int> _upperBound(Map<String, Object?> context) async {
    final sw = Stopwatch()..start();
    try {
      final bound = await db.transaction('pull seq barrier', (tx) async {
        await tx.execute(
          r"SELECT set_config('lock_timeout', $1, true)",
          parameters: ['${barrierTimeout.inMilliseconds}ms'],
          what: 'set seq barrier lock timeout',
          logParams: {'timeoutMs': barrierTimeout.inMilliseconds},
        );
        await tx.execute(
          'LOCK TABLE sync_seq_gate IN SHARE MODE',
          what: 'wait for open transactions holding seq',
          logParams: context,
        );
        final rows = await tx.execute(
          'SELECT last_value, is_called FROM change_seq',
          what: 'read last committed change seq',
          logParams: context,
        );
        final row = rows.single;
        final last = row[0]! as int;
        return row[1]! as bool ? last : last - 1;
      });
      if (bound > _safeBound) _safeBound = bound;
      _log.fine(
        'pull seq barrier passed bound=$bound '
        '${formatContext(context)} in ${sw.elapsedMilliseconds}ms',
      );
      return bound;
    } on pg.ServerException catch (e) {
      if (e.code != _lockNotAvailable) rethrow;
      _log.warning(
        'pull seq barrier timed out in ${sw.elapsedMilliseconds}ms '
        '(limit ${barrierTimeout.inMilliseconds}ms): a transaction that took '
        'a seq is still open, falling back to last safe bound=$_safeBound '
        '${formatContext(context)}',
      );
      return _safeBound;
    }
  }

  Future<({List<_Item> items, Set<_Kind> filled})> _read(
    String userId,
    SyncPullQuery query,
    int bound,
    Map<String, Object?> context,
  ) => db.transaction('sync pull', (tx) async {
    await tx.execute(
      'SET TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY',
      what: 'pull snapshot',
    );
    final fetchSize = query.limit + 1;
    final parameters = [userId, query.cursor, bound, fetchSize];
    final logParams = {...context, 'bound': bound};
    final filled = <_Kind>{};
    Future<List<_Item>> select(
      String what,
      String sql,
      _Kind kind,
      Object Function(pg.ResultRow row) decode,
      int seqColumn,
    ) async {
      final rows = await tx.execute(
        sql,
        parameters: parameters,
        what: what,
        logParams: logParams,
      );
      if (rows.length >= fetchSize) filled.add(kind);
      return [
        for (final row in rows)
          _Item(kind, row[seqColumn]! as int, decode(row)),
      ];
    }

    final items = [
      ...await select('pull budgets', _budgetsSql, _Kind.budget, _budget, 9),
      ...await select('pull members', _membersSql, _Kind.member, _member, 6),
      ...await select(
        'pull profiles',
        _profilesSql,
        _Kind.profile,
        _profile,
        5,
      ),
      ...await select(
        'pull categories',
        _categoriesSql,
        _Kind.category,
        _category,
        10,
      ),
      ...await select(
        'pull expenses',
        _expensesSql,
        _Kind.expense,
        _expense,
        13,
      ),
      ...await select(
        'pull recurring',
        _recurringSql,
        _Kind.recurring,
        _recurring,
        11,
      ),
      ...await select(
        'pull removed budgets',
        _removedSql,
        _Kind.removed,
        (row) => row[0]! as String,
        1,
      ),
    ];
    return (items: items, filled: filled);
  });
}

({List<_Item> items, bool hasMore}) _cut(
  List<_Item> items,
  int limit, {
  required Set<_Kind> filled,
}) {
  items.sort((a, b) {
    final bySeq = a.seq.compareTo(b.seq);
    return bySeq != 0 ? bySeq : a.kind.index.compareTo(b.kind.index);
  });
  var take = min(items.length, limit);
  if (items.length > take) {
    final split = items[take].seq;
    var cut = take;
    while (cut > 0 && items[cut - 1].seq == split) {
      cut--;
    }
    if (cut > 0) {
      take = cut;
    } else {
      while (take < items.length && items[take].seq == split) {
        take++;
      }
    }
  }
  return (
    items: items.sublist(0, take),
    hasMore: items.length > take || filled.isNotEmpty,
  );
}

SyncPullResponse _response(List<_Item> items, int cursor, bool hasMore) {
  List<T> of<T>(_Kind kind) => [
    for (final item in items)
      if (item.kind == kind) item.value as T,
  ];
  return SyncPullResponse(
    budgets: of<Budget>(_Kind.budget),
    members: of<BudgetMember>(_Kind.member),
    profiles: of<MemberProfile>(_Kind.profile),
    categories: of<Category>(_Kind.category),
    expenses: of<Expense>(_Kind.expense),
    recurring: of<RecurringRule>(_Kind.recurring),
    removedBudgetIds: of<String>(_Kind.removed),
    cursor: items.isEmpty ? cursor : items.last.seq,
    hasMore: hasMore,
  );
}

Budget _budget(pg.ResultRow row) => Budget(
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

BudgetMember _member(pg.ResultRow row) => BudgetMember(
  budgetId: row[0]! as String,
  userId: row[1]! as String,
  role: MemberRole.values.byName(row[2]! as String),
  avatarColor: CategoryColor.values.byName(row[3]! as String),
  joinedAt: row[4]! as DateTime,
  leftAt: row[5] as DateTime?,
);

MemberProfile _profile(pg.ResultRow row) => MemberProfile(
  userId: row[0]! as String,
  displayName: row[1]! as String,
  birthday: MonthDay.fromParts(row[2] as int?, row[3] as int?),
  avatarColor: CategoryColor.values.byName(row[4]! as String),
);

Category _category(pg.ResultRow row) => Category(
  id: row[0]! as String,
  budgetId: row[1]! as String,
  name: row[2]! as String,
  emoji: row[3]! as String,
  color: row[4] == null ? null : CategoryColor.values.byName(row[4]! as String),
  sortOrder: row[5]! as int,
  isSystem: row[6]! as bool,
  updatedAt: row[7]! as DateTime,
  updatedBy: row[8]! as String,
  deletedAt: row[9] as DateTime?,
  seq: row[10]! as int,
);

Expense _expense(pg.ResultRow row) => Expense(
  id: row[0]! as String,
  budgetId: row[1]! as String,
  categoryId: row[2]! as String,
  amount: Money(row[3]! as int),
  spentOn: LocalDate.parse(row[4]! as String),
  comment: row[5]! as String,
  authorId: row[6]! as String,
  recurringId: row[7] as String?,
  recurringMonth: row[8] == null ? null : YearMonth.parse(row[8]! as String),
  createdAt: row[9]! as DateTime,
  updatedAt: row[10]! as DateTime,
  updatedBy: row[11]! as String,
  deletedAt: row[12] as DateTime?,
  seq: row[13]! as int,
);

RecurringRule _recurring(pg.ResultRow row) => RecurringRule(
  id: row[0]! as String,
  budgetId: row[1]! as String,
  categoryId: row[2]! as String,
  title: row[3]! as String,
  amount: Money(row[4]! as int),
  dayOfMonth: row[5]! as int,
  startMonth: YearMonth.parse(row[6]! as String),
  createdAt: row[7]! as DateTime,
  updatedAt: row[8]! as DateTime,
  updatedBy: row[9]! as String,
  deletedAt: row[10] as DateTime?,
  seq: row[11]! as int,
);
