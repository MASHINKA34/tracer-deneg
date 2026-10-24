import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milionchik/core/clock.dart';
import 'package:milionchik/core/router.dart';
import 'package:milionchik/data/current_user.dart';
import 'package:milionchik/data/db/app_database.dart';
import 'package:milionchik/data/providers.dart';
import 'package:milionchik/data/repositories/categories_repository.dart';
import 'package:milionchik/data/repositories/expenses_repository.dart';
import 'package:milionchik/data/repositories/members_repository.dart';
import 'package:milionchik/data/repositories/outbox_queue.dart';
import 'package:milionchik/data/repositories/prefs_repository.dart';
import 'package:milionchik/data/session/session_providers.dart';
import 'package:milionchik/data/session/session_state.dart';
import 'package:milionchik/l10n/app_localizations.dart';
import 'package:milionchik/ui/theme/app_theme.dart';
import 'package:shared/shared.dart';

import '../../support/app_scope.dart';
import '../../support/golden.dart';
import '../../support/test_fonts.dart';
import '../profile/profile_fixture.dart';

const String familyId = profileFamilyId;

const String personalId = profilePersonalId;

const String meId = profileUserId;

const String dimaId = 'user-server-dima';

const String mamaId = 'user-server-mama';

const String foodId = 'authors-food';

const String homeId = 'authors-home';

const String healthId = 'authors-health';

const String shopId = 'authors-shop';

const String coffeeId = 'authors-coffee';

enum MamaState { member, left, deleted, noProfile }

final DateTime _created = DateTime(2026, 9, 28, 10);

final LocalDate authorsDay = LocalDate(2026, 10, 19);

String familyCategory(int index) => 'authors-family-cat-$index';

String personalCategory(int index) => 'authors-personal-cat-$index';

Future<void> seedAuthors(
  AppDatabase db, {
  MamaState mama = MamaState.member,
  bool shared = true,
  bool shop = false,
}) async {
  final at = _created.toUtc();
  await testBudgets(db).applyFromServer([
    Budget(
      id: personalId,
      kind: BudgetKind.personal,
      name: 'Личный бюджет',
      emoji: '👛',
      ownerId: meId,
      createdAt: at,
      updatedAt: at,
      updatedBy: meId,
    ),
    Budget(
      id: familyId,
      kind: BudgetKind.shared,
      name: 'Семья',
      emoji: '🏠',
      ownerId: meId,
      createdAt: at,
      updatedAt: at,
      updatedBy: meId,
    ),
  ]);
  final prefs = DriftPrefsRepository(db);
  final current = LocalPrefsCurrentUser(prefs);
  final outbox = DriftOutboxQueue(db);
  final categories = DriftCategoriesRepository(
    db,
    currentUser: current,
    outbox: outbox,
  );
  for (final (budgetId, id) in [
    (familyId, familyCategory),
    (personalId, personalCategory),
  ]) {
    var next = 0;
    await categories.applyFromServer(
      buildPresetCategories(
        budgetId: budgetId,
        updatedBy: meId,
        now: at,
        newId: () => id(next++),
      ),
    );
  }
  final members = DriftMembersRepository(db);
  final mamaLeft = mama == MamaState.left || mama == MamaState.deleted
      ? DateTime.utc(2026, 10, 19, 6)
      : null;
  await members.applyMembersFromServer([
    BudgetMember(
      budgetId: personalId,
      userId: meId,
      role: MemberRole.owner,
      avatarColor: CategoryColor.blue,
      joinedAt: at,
    ),
    BudgetMember(
      budgetId: familyId,
      userId: meId,
      role: MemberRole.owner,
      avatarColor: CategoryColor.blue,
      joinedAt: at,
    ),
    BudgetMember(
      budgetId: familyId,
      userId: dimaId,
      role: MemberRole.member,
      avatarColor: CategoryColor.green,
      joinedAt: DateTime.utc(2026, 10, 2, 6),
    ),
    BudgetMember(
      budgetId: familyId,
      userId: mamaId,
      role: MemberRole.member,
      avatarColor: CategoryColor.pink,
      joinedAt: DateTime.utc(2026, 10, 10, 17),
      leftAt: mamaLeft,
    ),
  ]);
  await members.applyProfilesFromServer([
    const MemberProfile(
      userId: dimaId,
      displayName: 'Дима',
      avatarColor: CategoryColor.green,
    ),
    if (mama != MamaState.noProfile)
      MemberProfile(
        userId: mamaId,
        displayName: mama == MamaState.deleted ? 'Удалённый участник' : 'Мама',
        avatarColor: CategoryColor.pink,
      ),
  ]);
  Expense expense(
    String id, {
    required String budgetId,
    required String categoryId,
    required int kopecks,
    required String comment,
    required String author,
    required DateTime created,
  }) => Expense(
    id: id,
    budgetId: budgetId,
    categoryId: categoryId,
    amount: Money(kopecks),
    spentOn: authorsDay,
    comment: comment,
    authorId: author,
    createdAt: created.toUtc(),
    updatedAt: created.toUtc(),
    updatedBy: author,
  );
  await DriftExpensesRepository(
    db,
    currentUser: current,
    outbox: outbox,
  ).applyFromServer([
    expense(
      foodId,
      budgetId: familyId,
      categoryId: familyCategory(0),
      kopecks: 234000,
      comment: 'Лента',
      author: dimaId,
      created: DateTime(2026, 10, 19, 12, 5),
    ),
    expense(
      homeId,
      budgetId: familyId,
      categoryId: familyCategory(3),
      kopecks: 512000,
      comment: 'Коммуналка',
      author: meId,
      created: DateTime(2026, 10, 19, 9, 30),
    ),
    expense(
      healthId,
      budgetId: familyId,
      categoryId: familyCategory(4),
      kopecks: 68000,
      comment: 'Аптека',
      author: mamaId,
      created: DateTime(2026, 10, 19, 8),
    ),
    if (shop)
      expense(
        shopId,
        budgetId: familyId,
        categoryId: familyCategory(0),
        kopecks: 64000,
        comment: 'Пятёрочка',
        author: dimaId,
        created: DateTime(2026, 10, 19, 14, 20),
      ),
    expense(
      coffeeId,
      budgetId: personalId,
      categoryId: personalCategory(1),
      kopecks: 32000,
      comment: 'Кофе',
      author: meId,
      created: DateTime(2026, 10, 19, 11),
    ),
  ]);
  await prefs.setString(
    PrefKeys.selectedBudgetId,
    shared ? familyId : personalId,
  );
}

Future<void> pumpAuthorsApp(
  WidgetTester tester,
  AppDatabase db, {
  required String location,
  Brightness brightness = Brightness.light,
  double width = 360,
  double scale = 1,
}) async {
  await loadTestFonts();
  tester.view
    ..devicePixelRatio = goldenPixelRatio
    ..physicalSize = Size(width, 800) * goldenPixelRatio
    ..viewPadding = const FakeViewPadding(top: 32)
    ..padding = const FakeViewPadding(top: 32);
  addTearDown(tester.view.reset);
  tester.platformDispatcher
    ..textScaleFactorTestValue = scale
    ..accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
      disableAnimations: true,
    );
  addTearDown(tester.platformDispatcher.clearAllTestValues);

  final router = buildRouter(initialLocation: location);
  addTearDown(router.dispose);
  final base = AppTheme.build(brightness, Mood.autumn);

  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(Clock(now: () => testNow)),
        sessionProvider.overrideWithBuild(
          (ref, _) => const SessionActive(profileUser),
        ),
      ],
      child: RepaintBoundary(
        key: goldenKey,
        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,
          theme: base.copyWith(
            textTheme: base.textTheme.apply(
              fontFamilyFallback: const [testEmojiFamily],
            ),
          ),
          locale: const Locale('ru'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          routerConfig: router,
        ),
      ),
    ),
  );
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
  }
  await settleAssets(tester);
}
