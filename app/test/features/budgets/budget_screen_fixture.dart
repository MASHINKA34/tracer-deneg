import 'dart:io';

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:milionchik/data/current_user.dart';
import 'package:milionchik/data/db/app_database.dart';
import 'package:milionchik/data/repositories/categories_repository.dart';
import 'package:milionchik/data/repositories/expenses_repository.dart';
import 'package:milionchik/data/repositories/members_repository.dart';
import 'package:milionchik/data/repositories/outbox_queue.dart';
import 'package:milionchik/data/repositories/prefs_repository.dart';
import 'package:milionchik/features/budgets/budget_screen.dart';
import 'package:milionchik/ui/components/snackbar.dart';
import 'package:shared/shared.dart';

import '../../data/api/fake_api_adapter.dart';
import '../../support/app_scope.dart';
import '../profile/profile_fixture.dart';
import '../profile/profile_harness.dart';

const String familyId = profileFamilyId;

const String dimaId = 'user-server-dima';

const String mamaId = 'user-server-mama';

const String familyCategory = 'family-cat';

final DateTime _created = DateTime(2026, 9, 28, 10);

final class BudgetScreenFixture {
  const BudgetScreenFixture._();

  static String category(int index) => '$familyCategory-$index';

  static Future<void> seed(
    AppDatabase db, {
    required bool owner,
    bool expenses = true,
  }) async {
    final ownerId = owner ? profileUserId : dimaId;
    await testBudgets(db).applyFromServer([
      Budget(
        id: profilePersonalId,
        kind: BudgetKind.personal,
        name: 'Личный бюджет',
        emoji: '👛',
        ownerId: profileUserId,
        createdAt: _created.toUtc(),
        updatedAt: _created.toUtc(),
        updatedBy: profileUserId,
      ),
      Budget(
        id: familyId,
        kind: BudgetKind.shared,
        name: 'Семья',
        emoji: '🏠',
        ownerId: ownerId,
        createdAt: _created.toUtc(),
        updatedAt: _created.toUtc(),
        updatedBy: ownerId,
      ),
    ]);
    final current = LocalPrefsCurrentUser(DriftPrefsRepository(db));
    final outbox = DriftOutboxQueue(db);
    var next = 0;
    await DriftCategoriesRepository(
      db,
      currentUser: current,
      outbox: outbox,
    ).applyFromServer(
      buildPresetCategories(
        budgetId: familyId,
        updatedBy: ownerId,
        now: _created.toUtc(),
        newId: () => category(next++),
      ),
    );
    final first = owner ? profileUserId : dimaId;
    final second = owner ? dimaId : profileUserId;
    final members = DriftMembersRepository(db);
    await members.applyMembersFromServer([
      BudgetMember(
        budgetId: profilePersonalId,
        userId: profileUserId,
        role: MemberRole.owner,
        avatarColor: CategoryColor.blue,
        joinedAt: _created.toUtc(),
      ),
      for (final (userId, role, color, joined) in [
        (first, MemberRole.owner, _colorOf(first), _created),
        (second, MemberRole.member, _colorOf(second), DateTime(2026, 10, 2, 9)),
        (
          mamaId,
          MemberRole.member,
          CategoryColor.pink,
          DateTime(2026, 10, 10, 20),
        ),
      ])
        BudgetMember(
          budgetId: familyId,
          userId: userId,
          role: role,
          avatarColor: color,
          joinedAt: joined.toUtc(),
        ),
    ]);
    await members.applyProfilesFromServer(const [
      MemberProfile(
        userId: dimaId,
        displayName: 'Дима',
        avatarColor: CategoryColor.green,
      ),
      MemberProfile(
        userId: mamaId,
        displayName: 'Мама',
        avatarColor: CategoryColor.pink,
      ),
    ]);
    if (!expenses) return;
    await DriftExpensesRepository(
      db,
      currentUser: current,
      outbox: outbox,
    ).applyFromServer([
      _expense(
        'expense-food',
        category: 0,
        kopecks: 234000,
        day: LocalDate(2026, 10, 19),
        comment: 'Лента',
        author: dimaId,
        created: DateTime(2026, 10, 19, 12, 5),
      ),
      _expense(
        'expense-home',
        category: 3,
        kopecks: 512000,
        day: LocalDate(2026, 10, 18),
        comment: 'Коммуналка',
        author: profileUserId,
        created: DateTime(2026, 10, 19, 9, 30),
      ),
      _expense(
        'expense-health',
        category: 4,
        kopecks: 68000,
        day: LocalDate(2026, 10, 17),
        comment: 'Аптека',
        author: mamaId,
        created: DateTime(2026, 10, 18, 8),
      ),
    ]);
  }

  static CategoryColor _colorOf(String userId) =>
      userId == profileUserId ? CategoryColor.blue : CategoryColor.green;

  static Expense _expense(
    String id, {
    required int category,
    required int kopecks,
    required LocalDate day,
    required String comment,
    required String author,
    required DateTime created,
  }) => Expense(
    id: id,
    budgetId: familyId,
    categoryId: BudgetScreenFixture.category(category),
    amount: Money(kopecks),
    spentOn: day,
    comment: comment,
    authorId: author,
    createdAt: created.toUtc(),
    updatedAt: created.toUtc(),
    updatedBy: author,
  );

  static Future<void> addExpenses(AppDatabase db, int count) =>
      DriftExpensesRepository(
        db,
        currentUser: LocalPrefsCurrentUser(DriftPrefsRepository(db)),
        outbox: DriftOutboxQueue(db),
      ).applyFromServer([
        for (var i = 0; i < count; i++)
          _expense(
            'expense-extra-$i',
            category: 2,
            kopecks: 10000 + i,
            day: LocalDate(2026, 10, 1),
            comment: '',
            author: dimaId,
            created: DateTime(2026, 10, 1, 8, i),
          ),
      ]);
}

DateTime inviteExpiry() => testNow.toUtc().add(const Duration(hours: 24));

final class BudgetServer {
  BudgetServer({required this.owner});

  final bool owner;
  final List<String> codes = ['MLN-48K2', 'MLN-7QXW', 'MLN-9TPZ'];
  final List<String> removedMembers = [];
  bool offline = false;
  bool pullOffline = false;
  bool left = false;
  bool deleted = false;
  bool excludedByOwner = false;
  bool deletedByOwner = false;
  FakeReply? reject;
  int issued = 0;
  int cursor = 500;

  String get _budget => '/budgets/$familyId';

  FakeReply handle(FakeCall call) {
    final path = call.path;
    if (call.method == 'GET' && path.endsWith('/sync/pull')) return _pull();
    if (offline) throw const SocketException('Connection refused (test)');
    final rejected = reject;
    if (rejected != null) return rejected;
    if (call.method == 'POST' && path.endsWith('$_budget/invites')) {
      return FakeReply.json(201, {
        'code': codes[issued++],
        'expiresAt': encodeInstant(inviteExpiry()),
      });
    }
    if (call.method == 'POST' && path.endsWith('$_budget/leave')) {
      left = true;
      return const FakeReply(204);
    }
    if (call.method == 'DELETE' && path.contains('$_budget/members/')) {
      removedMembers.add(path.split('/').last);
      return const FakeReply(204);
    }
    if (call.method == 'DELETE' && path.endsWith(_budget)) {
      deleted = true;
      return const FakeReply(204);
    }
    throw StateError('unexpected ${call.method} $path');
  }

  FakeReply _pull() {
    if (pullOffline) {
      throw const SocketException('Network is unreachable (test)');
    }
    final gone = left || deleted || excludedByOwner || deletedByOwner;
    return FakeReply.json(
      200,
      SyncPullResponse(
        members: [
          for (final userId in removedMembers)
            BudgetMember(
              budgetId: familyId,
              userId: userId,
              role: MemberRole.member,
              avatarColor: userId == dimaId
                  ? CategoryColor.green
                  : CategoryColor.pink,
              joinedAt: DateTime(2026, 10, 2, 9).toUtc(),
              leftAt: testNow.toUtc(),
            ),
        ],
        removedBudgetIds: [if (gone) familyId],
        deletedBudgetIds: [if (deleted || deletedByOwner) familyId],
        cursor: ++cursor,
        hasMore: false,
      ).toJson(),
    );
  }
}

Future<ProfileHarness> openBudgetScreen(
  WidgetTester tester,
  BudgetServer server, {
  bool selected = false,
  bool expenses = true,
  List<Override> overrides = const [],
}) async {
  final db = openTestDatabase();
  await tester.runAsync(() async {
    await BudgetScreenFixture.seed(db, owner: server.owner, expenses: expenses);
    if (selected) {
      await DriftPrefsRepository(db)
          .setString(PrefKeys.selectedBudgetId, familyId);
    }
  });
  final h = await ProfileHarness.start(
    tester,
    server: server.handle,
    seed: false,
    db: db,
    overrides: overrides,
  );
  await h.openProfile();
  await h.tap(find.text('Семья').last);
  expect(find.byType(BudgetScreen), findsOneWidget);
  return h;
}

Finder snackbarWith(String text) =>
    find.descendant(of: find.byType(AppSnackbar), matching: find.text(text));

Future<void> dismissSnackbar(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 6));
  await tester.pumpAndSettle();
}

Future<void> longPressAndSettle(ProfileHarness h, Finder target) async {
  await h.tester.longPress(target);
  await h.settle();
}

Future<int> budgetRows(ProfileHarness h) async =>
    (await h.tester.runAsync(() => h.db.select(h.db.budgets).get()))!.length;
