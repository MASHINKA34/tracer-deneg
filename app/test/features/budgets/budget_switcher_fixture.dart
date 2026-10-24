import 'package:milionchik/data/current_user.dart';
import 'package:milionchik/data/db/app_database.dart';
import 'package:milionchik/data/repositories/categories_repository.dart';
import 'package:milionchik/data/repositories/expenses_repository.dart';
import 'package:milionchik/data/repositories/members_repository.dart';
import 'package:milionchik/data/repositories/outbox_queue.dart';
import 'package:milionchik/data/repositories/prefs_repository.dart';
import 'package:shared/shared.dart';

import '../../support/app_scope.dart';
import '../month/month_fixture.dart';

const String familyId = 'budget-shared-family';

const String familyOwnerId = 'user-server-dima';

const List<int> familyOctoberRubles = [25000, 12000, 4200];

final class SwitcherFixture {
  const SwitcherFixture({
    required this.personalId,
    required this.familyCategories,
  });

  final String personalId;
  final List<Category> familyCategories;

  Category get familyOther => familyCategories.firstWhere((c) => c.isSystem);

  Category familyNamed(String name) =>
      familyCategories.firstWhere((c) => c.name == name);

  static Future<SwitcherFixture> mockup(
    AppDatabase db, {
    List<Category> Function(List<Category> presets)? familyCategories,
  }) async {
    final personalId = await seedMockupOctober(db);
    final created = testNow.subtract(const Duration(days: 30)).toUtc();
    await testBudgets(db).applyFromServer([
      Budget(
        id: familyId,
        kind: BudgetKind.shared,
        name: 'Семья',
        emoji: '🏠',
        ownerId: familyOwnerId,
        createdAt: created,
        updatedAt: created,
        updatedBy: familyOwnerId,
      ),
    ]);
    final user = LocalPrefsCurrentUser(DriftPrefsRepository(db));
    final outbox = DriftOutboxQueue(db);
    final presets = buildPresetCategories(
      budgetId: familyId,
      updatedBy: familyOwnerId,
      now: created,
      newId: _ids('cat-family'),
    );
    final categories = familyCategories?.call(presets) ?? presets;
    await DriftCategoriesRepository(
      db,
      currentUser: user,
      outbox: outbox,
    ).applyFromServer(categories);
    final members = DriftMembersRepository(db);
    await members.applyMembersFromServer([
      for (final (i, (userId, color)) in const [
        ('user-server-anya', CategoryColor.blue),
        (familyOwnerId, CategoryColor.green),
        ('user-server-masha', CategoryColor.pink),
      ].indexed)
        BudgetMember(
          budgetId: familyId,
          userId: userId,
          role: userId == familyOwnerId ? MemberRole.owner : MemberRole.member,
          avatarColor: color,
          joinedAt: created.add(Duration(minutes: i)),
        ),
    ]);
    await members.applyProfilesFromServer(const [
      MemberProfile(
        userId: 'user-server-anya',
        displayName: 'Аня',
        avatarColor: CategoryColor.blue,
      ),
      MemberProfile(
        userId: familyOwnerId,
        displayName: 'Дима',
        avatarColor: CategoryColor.green,
      ),
      MemberProfile(
        userId: 'user-server-masha',
        displayName: 'Маша',
        avatarColor: CategoryColor.pink,
      ),
    ]);
    await DriftExpensesRepository(
      db,
      currentUser: user,
      outbox: outbox,
    ).applyFromServer([
      for (final (i, rubles) in familyOctoberRubles.indexed)
        if (categories.isNotEmpty)
          Expense(
            id: 'expense-family-$i',
            budgetId: familyId,
            categoryId: categories[i % categories.length].id,
            amount: Money.rubles(rubles),
            spentOn: LocalDate(2026, 10, 3 + i),
            authorId: familyOwnerId,
            createdAt: created,
            updatedAt: created,
            updatedBy: familyOwnerId,
          ),
    ]);
    return SwitcherFixture(
      personalId: personalId,
      familyCategories: categories,
    );
  }
}

String Function() _ids(String prefix) {
  var next = 0;
  return () => '$prefix-${next++}';
}
