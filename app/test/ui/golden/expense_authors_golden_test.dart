import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milionchik/core/clock.dart';
import 'package:milionchik/core/router.dart';
import 'package:milionchik/data/db/app_database.dart';
import 'package:milionchik/data/providers.dart';
import 'package:milionchik/data/repositories/members_repository.dart';
import 'package:milionchik/data/session/session_providers.dart';
import 'package:milionchik/data/session/session_state.dart';
import 'package:milionchik/features/budgets/budget_screen.dart';
import 'package:milionchik/features/month/day_sheet.dart';
import 'package:milionchik/features/search/search_screen.dart';
import 'package:milionchik/ui/components/sheet.dart';
import 'package:shared/shared.dart';

import '../../features/budgets/budget_screen_fixture.dart' as budget_screen;
import '../../features/budgets/expense_authors_fixture.dart';
import '../../features/profile/profile_fixture.dart';
import '../../support/app_scope.dart';
import '../../support/golden.dart';

String _name(Brightness brightness, double width, double scale) =>
    '${brightness.name}_${width.toInt()}'
    '${scale == 1 ? '' : '_x${scale.toInt()}'}';

Future<void> _scrollToEnd(WidgetTester tester) async {
  final scrollable = tester.state<ScrollableState>(
    find.byType(Scrollable).first,
  );
  scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
  await tester.pumpAndSettle();
  await settleAssets(tester);
}

Future<void> _markMamaDeleted(AppDatabase db) async {
  final members = DriftMembersRepository(db);
  await members.applyMembersFromServer([
    BudgetMember(
      budgetId: budget_screen.familyId,
      userId: budget_screen.mamaId,
      role: MemberRole.member,
      avatarColor: CategoryColor.pink,
      joinedAt: DateTime(2026, 10, 10, 20).toUtc(),
      leftAt: DateTime(2026, 10, 19, 9).toUtc(),
    ),
  ]);
  await members.applyProfilesFromServer(const [
    MemberProfile(
      userId: budget_screen.mamaId,
      displayName: 'Удалённый участник',
      avatarColor: CategoryColor.pink,
    ),
  ]);
}

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  for (final brightness in Brightness.values) {
    for (final width in const [360.0, 320.0]) {
      for (final scale in const [1.0, 2.0]) {
        final name = _name(brightness, width, scale);

        testWidgets('шторка дня общего бюджета: Дима, я и удалённый участник '
            'day_sheet_$name (Figma 13:1203)', (tester) async {
          final db = openTestDatabase();
          await tester.runAsync(() => seedAuthors(db, mama: MamaState.deleted));
          await pumpGolden(
            tester,
            brightness: brightness,
            width: width,
            textScale: scale,
            padding: const EdgeInsets.only(top: 36),
            background: (_) => Colors.transparent,
            child: ProviderScope(
              overrides: [
                appDatabaseProvider.overrideWithValue(db),
                clockProvider.overrideWithValue(Clock(now: () => testNow)),
                sessionProvider.overrideWithBuild(
                  (ref, _) => const SessionActive(profileUser),
                ),
              ],
              child: AppSheet(children: [DaySheet(day: authorsDay)]),
            ),
          );
          await tester.pumpAndSettle();
          await settleAssets(tester);

          expect(find.text('Удалённый участник'), findsNothing);
          expect(tester.takeException(), isNull);
          await expectGolden(tester, 'expense_authors', 'day_sheet_$name');
        });

        testWidgets('«Трата» общего бюджета: «Добавил: Дима» edit_$name '
            '(Figma 43:4368)', (tester) async {
          final db = openTestDatabase();
          await tester.runAsync(() => seedAuthors(db, shop: true));
          debugDisableShadows = false;
          await pumpAuthorsApp(
            tester,
            db,
            location: AppRoutes.expenseOf(shopId),
            brightness: brightness,
            width: width,
            scale: scale,
          );
          if (scale != 1) await _scrollToEnd(tester);

          expect(find.text('Добавил: Дима'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await expectGolden(tester, 'expense_authors', 'edit_$name');
        });
      }
    }

    final name = _name(brightness, 360, 1);

    testWidgets('«Трата» удалённого участника: «Добавил: Удалённый '
        'участник» серым edit_removed_$name', (tester) async {
      final db = openTestDatabase();
      await tester.runAsync(() => seedAuthors(db, mama: MamaState.deleted));
      debugDisableShadows = false;
      await pumpAuthorsApp(
        tester,
        db,
        location: AppRoutes.expenseOf(healthId),
        brightness: brightness,
      );

      expect(find.text('Добавил: Удалённый участник'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await expectGolden(tester, 'expense_authors', 'edit_removed_$name');
    });

    testWidgets('экран бюджета: Мама удалила аккаунт - в последних тратах '
        'нейтральный аватар budget_removed_$name (Figma 13:1135)', (
      tester,
    ) async {
      final db = openTestDatabase();
      await tester.runAsync(() async {
        await budget_screen.BudgetScreenFixture.seed(db, owner: true);
        await _markMamaDeleted(db);
      });
      debugDisableShadows = false;
      await pumpAuthorsApp(
        tester,
        db,
        location: AppRoutes.budgetOf(budget_screen.familyId),
        brightness: brightness,
      );

      expect(find.byType(BudgetScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
      await expectGolden(tester, 'expense_authors', 'budget_removed_$name');
    });

    testWidgets('главная общего бюджета: «Сегодня» с авторами '
        'month_$name', (tester) async {
      final db = openTestDatabase();
      await tester.runAsync(() => seedAuthors(db, mama: MamaState.deleted));
      debugDisableShadows = false;
      await pumpAuthorsApp(
        tester,
        db,
        location: AppRoutes.month,
        brightness: brightness,
      );
      await _scrollToEnd(tester);

      expect(tester.takeException(), isNull);
      await expectGolden(tester, 'expense_authors', 'month_$name');
    });

    testWidgets('поиск в общем бюджете: строки с авторами search_$name', (
      tester,
    ) async {
      final db = openTestDatabase();
      await tester.runAsync(() => seedAuthors(db, mama: MamaState.deleted));
      EditableText.debugDeterministicCursor = true;
      addTearDown(() => EditableText.debugDeterministicCursor = false);
      debugDisableShadows = false;
      await pumpAuthorsApp(
        tester,
        db,
        location: AppRoutes.search,
        brightness: brightness,
      );
      await tester.enterText(find.byType(EditableText), 'а');
      await tester.pump(searchDebounce);
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      await settleAssets(tester);

      expect(find.byType(SearchScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
      await expectGolden(tester, 'expense_authors', 'search_$name');
    });
  }
}
