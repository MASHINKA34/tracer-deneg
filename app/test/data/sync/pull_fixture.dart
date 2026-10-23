import 'dart:async';

import 'package:milionchik/data/api/api_client.dart';
import 'package:milionchik/data/api/api_config.dart';
import 'package:milionchik/data/api/sync_api.dart';
import 'package:milionchik/data/api/token_store.dart';
import 'package:milionchik/data/current_user.dart';
import 'package:milionchik/data/db/app_database.dart';
import 'package:milionchik/data/repositories/budgets_repository.dart';
import 'package:milionchik/data/repositories/categories_repository.dart';
import 'package:milionchik/data/repositories/expenses_repository.dart';
import 'package:milionchik/data/repositories/members_repository.dart';
import 'package:milionchik/data/repositories/outbox_queue.dart';
import 'package:milionchik/data/repositories/recurring_repository.dart';
import 'package:milionchik/data/sync/pull_service.dart';
import 'package:shared/shared.dart';

import '../api/fake_api_adapter.dart';

const String pullUserId = 'user-server-77';

const String pullAccess = 'ACCESS-pull-quebec-romeo-sierra';

const String pullRefresh = 'REFRESH-pull-tango-uniform-victor';

final DateTime pullT0 = DateTime.utc(2026, 10, 19, 9);

final ApiConfig pullApiConfig = ApiConfig.resolve(define: '', debugBuild: true);

Budget serverPersonal({
  String id = 'budget-personal',
  String ownerId = pullUserId,
  int seq = 1,
  DateTime? createdAt,
}) => Budget(
  id: id,
  kind: BudgetKind.personal,
  name: DriftBudgetsRepository.personalName,
  emoji: DriftBudgetsRepository.personalEmoji,
  ownerId: ownerId,
  createdAt: createdAt ?? pullT0,
  updatedAt: createdAt ?? pullT0,
  updatedBy: ownerId,
  seq: seq,
);

Budget serverShared({
  String id = 'budget-family',
  String ownerId = 'user-other',
  int seq = 1,
}) => Budget(
  id: id,
  kind: BudgetKind.shared,
  name: 'Семья',
  emoji: '🏠',
  ownerId: ownerId,
  createdAt: pullT0,
  updatedAt: pullT0,
  updatedBy: ownerId,
  seq: seq,
);

BudgetMember ownerOf(String budgetId, {String userId = pullUserId}) =>
    BudgetMember(
      budgetId: budgetId,
      userId: userId,
      role: MemberRole.owner,
      avatarColor: CategoryColor.blue,
      joinedAt: pullT0,
    );

List<Category> serverPresets(String budgetId, {int firstSeq = 2}) {
  var n = 0;
  var seq = firstSeq;
  return [
    for (final c in buildPresetCategories(
      budgetId: budgetId,
      updatedBy: pullUserId,
      now: pullT0,
      newId: () => '$budgetId-cat-${n++}',
    ))
      c.copyWith(seq: seq++),
  ];
}

Expense serverExpense({
  required String id,
  required String budgetId,
  required String categoryId,
  int kopecks = 64000,
  LocalDate? spentOn,
  String comment = '',
  DateTime? deletedAt,
  required int seq,
}) => Expense(
  id: id,
  budgetId: budgetId,
  categoryId: categoryId,
  amount: Money(kopecks),
  spentOn: spentOn ?? LocalDate(2026, 10, 19),
  comment: comment,
  authorId: pullUserId,
  createdAt: pullT0,
  updatedAt: deletedAt ?? pullT0,
  updatedBy: pullUserId,
  deletedAt: deletedAt,
  seq: seq,
);

typedef PullStep = FutureOr<Object?> Function(FakeCall call);

final class FakePullServer {
  FakePullServer(List<SyncPullResponse> pages) : pages = [...pages];

  final List<SyncPullResponse> pages;

  final Map<int, PullStep> before = {};

  final List<int> cursors = [];

  late final FakeApiAdapter adapter = FakeApiAdapter(handle);

  int _rid = 0;

  String nextRequestId() => 'ridpull${(++_rid).toString().padLeft(9, '0')}';

  Future<FakeReply> handle(FakeCall call) async {
    if (!call.path.endsWith(pullPath)) {
      throw StateError('unexpected ${call.method} ${call.path}');
    }
    final cursor = int.parse(call.options.uri.queryParameters['cursor']!);
    cursors.add(cursor);
    var index = 0;
    var start = 0;
    while (index < pages.length && start != cursor) {
      start = pages[index].cursor;
      index++;
    }
    final step = before[index + 1];
    if (step != null) {
      final reply = await step(call);
      if (reply is FakeReply) return reply;
    }
    if (index >= pages.length) {
      return FakeReply.json(
        200,
        SyncPullResponse(cursor: cursor, hasMore: false).toJson(),
      );
    }
    return FakeReply.json(200, pages[index].toJson());
  }
}

ApiClient pullApiClient(FakePullServer server, {TokenStore? tokens}) =>
    ApiClient(
      config: pullApiConfig,
      tokens:
          tokens ??
          MemoryTokenStore(
            const AuthTokens(
              accessToken: pullAccess,
              refreshToken: pullRefresh,
            ),
          ),
      adapter: server.adapter,
      newRequestId: server.nextRequestId,
    );

final class PullRig {
  PullRig(this.db, this.server, {DateTime Function()? now})
    : now = now ?? (() => DateTime.utc(2026, 10, 19, 15, 40));

  final AppDatabase db;
  final FakePullServer server;
  final DateTime Function() now;

  late final CurrentUser user = SessionCurrentUser(pullUserId);
  late final DriftOutboxQueue outbox = DriftOutboxQueue(db, now: now);
  late final DriftBudgetsRepository budgets = DriftBudgetsRepository(
    db,
    currentUser: user,
    outbox: outbox,
    now: now,
  );

  PullService service({ExpensesRepository? expenses}) => PullService(
    api: SyncApi(pullApiClient(server)),
    db: db,
    budgets: budgets,
    members: DriftMembersRepository(db),
    categories: DriftCategoriesRepository(
      db,
      currentUser: user,
      outbox: outbox,
      now: now,
    ),
    recurring: DriftRecurringRepository(
      db,
      currentUser: user,
      outbox: outbox,
      now: now,
    ),
    expenses:
        expenses ??
        DriftExpensesRepository(
          db,
          currentUser: user,
          outbox: outbox,
          now: now,
        ),
    now: now,
  );

  Future<SyncStateEntry> syncState() =>
      (db.select(db.syncStates)..where((s) => s.id.equals(0))).getSingle();

  Future<int> count(String table) async {
    final row = await db
        .customSelect('SELECT count(*) AS n FROM $table')
        .getSingle();
    return row.read<int>('n');
  }
}
