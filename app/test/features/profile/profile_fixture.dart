import 'package:drift/drift.dart' show Value;
import 'package:milionchik/data/current_user.dart';
import 'package:milionchik/data/db/app_database.dart';
import 'package:milionchik/data/repositories/categories_repository.dart';
import 'package:milionchik/data/repositories/members_repository.dart';
import 'package:milionchik/data/repositories/outbox_queue.dart';
import 'package:milionchik/data/repositories/prefs_repository.dart';
import 'package:milionchik/data/session/session.dart';
import 'package:shared/shared.dart';

import '../../support/app_scope.dart';

const String profileUserId = 'user-server-77';

const SessionUser profileUser = SessionUser(
  userId: profileUserId,
  login: 'anya_m',
  displayName: 'Аня',
);

const String profilePersonalId = 'budget-personal-anya';

const String profileFamilyId = 'budget-shared-family';

final DateTime profileLastSync = testNow.subtract(const Duration(minutes: 2));

final class ProfileFixture {
  const ProfileFixture(this.db);

  final AppDatabase db;

  static Future<ProfileFixture> mockup(
    AppDatabase db, {
    DateTime? lastSyncAt,
    bool synced = true,
  }) async {
    final fixture = ProfileFixture(db);
    final created = testNow.subtract(const Duration(days: 30)).toUtc();
    await testBudgets(db).applyFromServer([
      Budget(
        id: profilePersonalId,
        kind: BudgetKind.personal,
        name: 'Личный бюджет',
        emoji: '👛',
        ownerId: profileUserId,
        createdAt: created,
        updatedAt: created,
        updatedBy: profileUserId,
      ),
      Budget(
        id: profileFamilyId,
        kind: BudgetKind.shared,
        name: 'Семья',
        emoji: '🏠',
        ownerId: 'user-server-dima',
        createdAt: created,
        updatedAt: created,
        updatedBy: 'user-server-dima',
      ),
    ]);
    await DriftCategoriesRepository(
      db,
      currentUser: LocalPrefsCurrentUser(DriftPrefsRepository(db)),
      outbox: DriftOutboxQueue(db),
    ).applyFromServer(
      buildPresetCategories(
        budgetId: profilePersonalId,
        updatedBy: profileUserId,
        now: created,
        newId: _ids('cat-personal'),
      ),
    );
    final members = DriftMembersRepository(db);
    await members.applyMembersFromServer([
      for (final (i, (userId, color)) in const [
        (profileUserId, CategoryColor.blue),
        ('user-server-dima', CategoryColor.green),
        ('user-server-masha', CategoryColor.pink),
      ].indexed)
        BudgetMember(
          budgetId: profileFamilyId,
          userId: userId,
          role: i == 1 ? MemberRole.owner : MemberRole.member,
          avatarColor: color,
          joinedAt: created.add(Duration(minutes: i)),
        ),
    ]);
    await members.applyProfilesFromServer(const [
      MemberProfile(
        userId: profileUserId,
        displayName: 'Аня',
        avatarColor: CategoryColor.blue,
      ),
      MemberProfile(
        userId: 'user-server-dima',
        displayName: 'Дима',
        avatarColor: CategoryColor.green,
      ),
      MemberProfile(
        userId: 'user-server-masha',
        displayName: 'Маша',
        avatarColor: CategoryColor.pink,
      ),
    ]);
    if (synced) await fixture.setLastSync(lastSyncAt ?? profileLastSync);
    return fixture;
  }

  Future<void> setLastSync(DateTime at) =>
      (db.update(db.syncStates)..where((s) => s.id.equals(0))).write(
        SyncStatesCompanion(lastSyncAt: Value(at.toUtc())),
      );
}

String Function() _ids(String prefix) {
  var next = 0;
  return () => '$prefix-${next++}';
}
