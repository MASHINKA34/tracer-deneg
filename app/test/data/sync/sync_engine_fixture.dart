import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:milionchik/data/api/api_client.dart';
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
import 'package:milionchik/data/sync/budget_removed_notice.dart';
import 'package:milionchik/data/sync/pull_service.dart';
import 'package:milionchik/data/sync/sync_engine.dart';
import 'package:shared/shared.dart';

import '../../support/app_scope.dart';
import '../api/fake_api_adapter.dart';
import 'pull_fixture.dart';

const String engineUserId = pullUserId;

const String familyBudgetId = 'budget-family';

void allowSeveralPhones() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  tearDownAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false);
}

final class TestClock {
  TestClock(this.now);

  DateTime now;

  void advance(Duration by) => now = now.add(by);
}

final class FakeTimer implements Timer {
  FakeTimer(this.duration, this._callback);

  final Duration duration;
  final void Function() _callback;
  bool _active = true;

  @override
  bool get isActive => _active;

  @override
  int get tick => 0;

  @override
  void cancel() => _active = false;

  void fire() {
    if (!_active) throw StateError('timer $duration is not active');
    _active = false;
    _callback();
  }
}

final class FakeTimers {
  final List<FakeTimer> all = [];

  Timer start(Duration delay, void Function() callback) {
    final timer = FakeTimer(delay, callback);
    all.add(timer);
    return timer;
  }

  List<FakeTimer> get active => [
    for (final t in all)
      if (t.isActive) t,
  ];

  List<Duration> get delays => [for (final t in all) t.duration];
}

final class StoredRecord {
  StoredRecord(this.record, this.seq);

  SyncRecord record;
  int seq;

  String get budgetId => switch (record) {
    Budget(:final id) => id,
    Category(:final budgetId) => budgetId,
    RecurringRule(:final budgetId) => budgetId,
    Expense(:final budgetId) => budgetId,
    _ => throw StateError('unknown record'),
  };
}

final class EngineServer {
  EngineServer({this.userId = engineUserId});

  final String userId;
  final Map<(SyncEntity, String), StoredRecord> records = {};
  final Set<String> memberOf = {};
  final Map<String, int> removed = {};
  final Map<String, SyncPushResponse> batches = {};
  final List<String> pushBatchIds = [];
  final List<int> pullCursors = [];
  final List<String> order = [];
  int seq = 0;
  int writes = 0;
  bool online = true;
  bool dropNextPushAnswer = false;
  FutureOr<FakeReply?> Function(FakeCall call)? beforePush;
  FutureOr<FakeReply?> Function(FakeCall call)? beforePull;
  int _inFlight = 0;
  int maxInFlight = 0;
  int _rid = 0;

  String nextRequestId() => 'ridengine${(++_rid).toString().padLeft(7, '0')}';

  void seed(SyncRecord record) {
    seq++;
    records[(record.syncEntity, record.id)] = StoredRecord(
      record.withSeq(seq),
      seq,
    );
    if (record is Budget) memberOf.add(record.id);
  }

  T stored<T extends SyncRecord>(SyncEntity entity, String id) =>
      records[(entity, id)]!.record as T;

  int countOf(SyncEntity entity) =>
      records.keys.where((k) => k.$1 == entity).length;

  void exclude(String budgetId) {
    memberOf.remove(budgetId);
    removed[budgetId] = ++seq;
  }

  Future<FakeReply> handle(FakeCall call) async {
    order.add('${call.method} ${call.path}');
    _inFlight++;
    if (_inFlight > maxInFlight) maxInFlight = _inFlight;
    try {
      if (!online) throw const SocketException('Network is unreachable');
      if (call.path.endsWith(pushPath)) {
        final hook = beforePush;
        if (hook != null) {
          final reply = await hook(call);
          if (reply != null) return reply;
        }
        final reply = _push(SyncPushRequest.fromJson(call.json));
        if (dropNextPushAnswer) {
          dropNextPushAnswer = false;
          throw const SocketException('Connection reset by peer');
        }
        return reply;
      }
      if (call.path.endsWith(pullPath)) {
        final hook = beforePull;
        if (hook != null) {
          final reply = await hook(call);
          if (reply != null) return reply;
        }
        final query = call.options.uri.queryParameters;
        return _pull(int.parse(query['cursor']!), int.parse(query['limit']!));
      }
      throw StateError('unexpected ${call.method} ${call.path}');
    } finally {
      _inFlight--;
    }
  }

  FakeReply _push(SyncPushRequest request) {
    pushBatchIds.add(request.batchId);
    final known = batches[request.batchId];
    if (known != null) return FakeReply.json(200, known.toJson());
    final applied = <String>[];
    final rejected = <SyncRejection>[];
    var cursor = 0;
    for (final change in request.changes) {
      final key = (change.entity, change.id);
      final current = records[key];
      String? code;
      if (change.op == SyncOp.delete) {
        if (current == null || !memberOf.contains(current.budgetId)) {
          code = 'not_found';
        } else if (current.record.deletedAt == null) {
          current.record = _tombstone(current.record, change.updatedAt);
          current.seq = ++seq;
          writes++;
        }
      } else {
        final record = change.decodeRecord();
        final target = StoredRecord(record, 0).budgetId;
        if (!memberOf.contains(target)) {
          code = 'not_found';
        } else if (current == null) {
          records[key] = StoredRecord(record.withSeq(++seq), seq);
          writes++;
        } else if (current.record.deletedAt != null ||
            change.updatedAt.isBefore(current.record.updatedAt)) {
          code = 'conflict';
        } else {
          current.record = record.withSeq(++seq);
          current.seq = seq;
          writes++;
        }
      }
      final visible = records[key]?.seq ?? 0;
      if (visible > cursor) cursor = visible;
      if (code == null) {
        applied.add(change.id);
      } else {
        rejected.add(SyncRejection(id: change.id, code: code));
      }
    }
    final response = SyncPushResponse(
      applied: applied,
      rejected: rejected,
      cursor: cursor,
    );
    batches[request.batchId] = response;
    return FakeReply.json(200, response.toJson());
  }

  FakeReply _pull(int cursor, int limit) {
    pullCursors.add(cursor);
    final items = [
      for (final r in records.values)
        if (r.seq > cursor && memberOf.contains(r.budgetId)) r,
    ]..sort((a, b) => a.seq.compareTo(b.seq));
    final removedNow = [
      for (final MapEntry(key: id, value: at) in removed.entries)
        if (at > cursor) (id, at),
    ];
    final page = items.take(limit).toList();
    final more = items.length > limit;
    var last = page.isEmpty ? cursor : page.last.seq;
    for (final (_, at) in removedNow) {
      if (at > last && !more) last = at;
    }
    List<T> of<T extends SyncRecord>() => [
      for (final r in page)
        if (r.record is T) r.record as T,
    ];
    return FakeReply.json(
      200,
      SyncPullResponse(
        budgets: of<Budget>(),
        categories: of<Category>(),
        expenses: of<Expense>(),
        recurring: of<RecurringRule>(),
        removedBudgetIds: [for (final (id, _) in removedNow) id],
        cursor: last,
        hasMore: more,
      ).toJson(),
    );
  }
}

SyncRecord _tombstone(SyncRecord record, DateTime at) {
  final updated = at.isAfter(record.updatedAt) ? at : record.updatedAt;
  return switch (record) {
    final Expense e => e.copyWith(deletedAt: at, updatedAt: updated),
    final Category c => c.copyWith(deletedAt: at, updatedAt: updated),
    final RecurringRule r => r.copyWith(deletedAt: at, updatedAt: updated),
    final Budget b => b.copyWith(deletedAt: at, updatedAt: updated),
    _ => throw StateError('unknown record'),
  };
}

extension on SyncRecord {
  SyncRecord withSeq(int seq) => switch (this) {
    final Expense e => e.copyWith(seq: seq),
    final Category c => c.copyWith(seq: seq),
    final RecurringRule r => r.copyWith(seq: seq),
    final Budget b => b.copyWith(seq: seq),
    _ => throw StateError('unknown record'),
  };
}

Budget engineFamily({String ownerId = 'user-other'}) => Budget(
  id: familyBudgetId,
  kind: BudgetKind.shared,
  name: 'Семья',
  emoji: '🏠',
  ownerId: ownerId,
  createdAt: pullT0,
  updatedAt: pullT0,
  updatedBy: ownerId,
);

Category engineCategory(String budgetId, {String? id}) => Category(
  id: id ?? '$budgetId-cat',
  budgetId: budgetId,
  name: 'Продукты',
  emoji: '🛒',
  color: CategoryColor.green,
  sortOrder: 0,
  isSystem: false,
  updatedAt: pullT0,
  updatedBy: engineUserId,
);

EngineServer seededServer({bool family = false, String? familyOwner}) {
  final server = EngineServer();
  server.seed(serverPersonal(seq: 0));
  server.seed(engineCategory('budget-personal'));
  if (family) {
    server.seed(engineFamily(ownerId: familyOwner ?? 'user-other'));
    server.seed(engineCategory(familyBudgetId));
  }
  return server;
}

final class EngineDevice {
  EngineDevice(
    this.server, {
    required this.name,
    required this.clock,
    this.random = 0.5,
  });

  final EngineServer server;
  final String name;
  final TestClock clock;
  final double random;
  final AppDatabase db = openTestDatabase();
  final FakeTimers timers = FakeTimers();
  final List<(RemovedBudget, BudgetRemovalKind)> notices = [];
  String? selected = 'budget-personal';
  bool signedIn = true;
  int _batch = 0;

  DateTime now() => clock.now;

  late final FakeApiAdapter adapter = FakeApiAdapter(server.handle);
  late final SyncApi api = SyncApi(
    ApiClient(
      config: pullApiConfig,
      tokens: MemoryTokenStore(
        const AuthTokens(accessToken: pullAccess, refreshToken: pullRefresh),
      ),
      adapter: adapter,
      newRequestId: server.nextRequestId,
    ),
  );
  late final CurrentUser user = const SessionCurrentUser(engineUserId);
  late final DriftOutboxQueue outbox = DriftOutboxQueue(db, now: now);
  late final DriftBudgetsRepository budgets = DriftBudgetsRepository(
    db,
    currentUser: user,
    outbox: outbox,
    now: now,
  );
  late final DriftCategoriesRepository categories = DriftCategoriesRepository(
    db,
    currentUser: user,
    outbox: outbox,
    now: now,
  );
  late final DriftExpensesRepository expenses = DriftExpensesRepository(
    db,
    currentUser: user,
    outbox: outbox,
    now: now,
  );
  late final PullService pull = PullService(
    api: api,
    db: db,
    budgets: budgets,
    members: DriftMembersRepository(db),
    categories: categories,
    recurring: DriftRecurringRepository(
      db,
      currentUser: user,
      outbox: outbox,
      now: now,
    ),
    expenses: expenses,
    now: now,
  );
  late final SyncEngine engine = SyncEngine(
    api: () => api,
    outbox: () => outbox,
    pullService: () => pull,
    signedInUserId: () => signedIn ? engineUserId : null,
    selectedBudgetId: () async => selected,
    onNotice: (budget, kind) => notices.add((budget, kind)),
    now: now,
    random: _FixedRandom(random),
    startTimer: timers.start,
    newBatchId: () => '$name-batch-${++_batch}',
  );

  Future<SyncCycleResult> sync([SyncReason reason = SyncReason.manual]) =>
      engine.sync(reason);

  Future<Expense> add(int rubles, {String budgetId = 'budget-personal'}) =>
      expenses.create(
        budgetId: budgetId,
        categoryId: '$budgetId-cat',
        amount: Money.rubles(rubles),
        spentOn: LocalDate(2026, 10, 19),
        comment: 'kommentariy-engine-oscar-papa',
      );

  Future<ExpenseEntry?> row(String id) =>
      (db.select(db.expenses)..where((e) => e.id.equals(id))).getSingleOrNull();

  Future<int> rows(String table) async =>
      (await db.customSelect('SELECT count(*) AS n FROM $table').getSingle())
          .read<int>('n');

  Future<void> fireRetry() async {
    timers.active.single.fire();
    await engine.whenIdle();
  }

  void dispose() => engine.dispose();
}

final class _FixedRandom implements math.Random {
  _FixedRandom(this.value);

  final double value;

  @override
  bool nextBool() => value >= 0.5;

  @override
  double nextDouble() => value;

  @override
  int nextInt(int max) => (value * max).floor();
}
