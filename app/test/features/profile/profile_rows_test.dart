import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milionchik/features/categories/categories_screen.dart';
import 'package:milionchik/features/export/export_screen.dart';
import 'package:milionchik/features/profile/profile_account_card.dart';
import 'package:milionchik/features/profile/profile_screen.dart';
import 'package:milionchik/features/profile/recovery_code_reissue_screen.dart';
import 'package:milionchik/features/profile/theme_screen.dart';
import 'package:milionchik/l10n/app_localizations.dart';
import 'package:milionchik/ui/components/avatar.dart';
import 'package:milionchik/ui/components/list_row.dart';
import 'package:milionchik/ui/components/snackbar.dart';

import '../../support/app_scope.dart';
import 'profile_fixture.dart';
import 'profile_harness.dart';

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testWidgets('профиль: аккаунт, бюджеты и строки настроек со значениями', (
    tester,
  ) async {
    final h = await ProfileHarness.start(tester);
    await h.openProfile();

    expect(find.byType(ProfileScreen), findsOneWidget);
    final card = find.byType(ProfileAccountCard);
    expect(
      find.descendant(of: card, matching: find.text('Аня')),
      findsOneWidget,
    );
    expect(find.text('логин: anya_m'), findsOneWidget);
    expect(find.text('Синхронизировано · 2 мин назад'), findsOneWidget);
    final avatar = tester.widget<AppAvatar>(
      find.descendant(of: card, matching: find.byType(AppAvatar)),
    );
    expect(avatar.letter, 'А');
    expect(avatar.size, AvatarSize.s64);

    expect(find.text('Бюджеты'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('Личный'), findsOneWidget);
    expect(find.text('Только ты · открыт сейчас'), findsOneWidget);
    expect(find.text('Семья'), findsOneWidget);
    expect(find.text('Общий · 3 участника'), findsOneWidget);
    expect(find.text('Создать общий бюджет'), findsOneWidget);
    expect(find.text('Войти по коду приглашения'), findsOneWidget);

    final rows = <String, String?>{
      'Праздники': 'скоро',
      'Категории': '10',
      'Тема': 'Как в системе',
      'Напоминания': 'скоро',
      'Экспорт трат в CSV': null,
      'Код восстановления': 'Перевыпустить',
      'Отправить логи разработчику': 'скоро',
      'Выйти': 'скоро',
      'Удалить аккаунт': 'скоро',
    };
    expect(
      tester.widgetList<ListRow>(find.byType(ListRow)).map((r) => r.title),
      rows.keys,
    );
    for (final MapEntry(key: title, value: value) in rows.entries) {
      expect(h.valueOf(title), value, reason: title);
      expect(
        tester.getSize(h.row(title)).height,
        greaterThanOrEqualTo(48),
        reason: title,
      );
    }
    final danger = tester
        .widgetList<ListRow>(find.byType(ListRow))
        .where((r) => r.danger)
        .map((r) => (r.title, r.chevron));
    expect(danger, [('Выйти', false), ('Удалить аккаунт', false)]);
    expect(
      h.linesOf('profile'),
      contains(matches(r'profile budgets shown count=2 shared=1 in \d+ms$')),
    );
  });

  testWidgets('статус синхронизации обновляется, когда pull записал '
      'lastSyncAt; без загрузок - «Ещё не синхронизировано»', (tester) async {
    final db = openTestDatabase();
    await tester.runAsync(() => ProfileFixture.mockup(db, synced: false));
    final h = await ProfileHarness.start(tester, db: db, seed: false);
    await h.openProfile();

    expect(find.text('Ещё не синхронизировано'), findsOneWidget);

    await tester.runAsync(
      () => ProfileFixture(db)
          .setLastSync(testNow.subtract(const Duration(hours: 3, minutes: 5))),
    );
    await h.settle();

    expect(find.text('Синхронизировано · 3 ч назад'), findsOneWidget);
    expect(find.text('Ещё не синхронизировано'), findsNothing);
  });

  testWidgets('без сессии карточки аккаунта нет, бюджеты и настройки на '
      'месте', (tester) async {
    final h = await ProfileHarness.start(tester, user: null);
    await h.openProfile();

    expect(find.byType(ProfileAccountCard), findsNothing);
    expect(h.row('Тема'), findsOneWidget);
    expect(
      h.linesOf('profile'),
      contains(endsWith('profile without session: account card hidden')),
    );
  });

  for (final (title, screen, log) in [
    ('Категории', CategoriesScreen, 'categories tap → /categories'),
    ('Тема', ThemeScreen, 'theme tap → /profile/theme'),
    ('Экспорт трат в CSV', ExportScreen, 'export tap → /export'),
    (
      'Код восстановления',
      RecoveryCodeReissueScreen,
      'recovery code tap → /profile/recovery-code',
    ),
  ]) {
    testWidgets('«$title» открывает свой экран, «назад» возвращает в '
        'профиль', (tester) async {
      final h = await ProfileHarness.start(tester);
      await h.openProfile();

      await h.tap(h.row(title));

      expect(find.byType(screen), findsOneWidget);
      expect(h.linesOf('profile'), contains(endsWith('profile row $log')));

      await tester.tap(find.bySemanticsLabel('Назад').last);
      await h.settle();

      expect(find.byType(screen), findsNothing);
      expect(find.byType(ProfileScreen), findsOneWidget);
      expect(h.row(title), findsOneWidget);
    });
  }

  for (final (target, stub) in [
    ('Праздники', 'holidays'),
    ('Напоминания', 'reminders'),
    ('Отправить логи разработчику', 'sendLogs'),
    ('Выйти', 'signOut'),
    ('Удалить аккаунт', 'deleteAccount'),
    ('Создать общий бюджет', 'createBudget'),
    ('Войти по коду приглашения', 'joinBudget'),
    ('Семья', 'budget'),
  ]) {
    testWidgets('«$target» - заглушка: снекбар «Появится в следующем '
        'обновлении», экран не меняется', (tester) async {
      final h = await ProfileHarness.start(tester);
      await h.openProfile();

      await h.tap(find.text(target).last);

      expect(
        find.descendant(
          of: find.byType(AppSnackbar),
          matching: find.text('Появится в следующем обновлении'),
        ),
        findsOneWidget,
      );
      expect(find.byType(ProfileScreen), findsOneWidget);
      expect(
        h.linesOf('profile'),
        contains(
          allOf(
            contains('profile $stub tap'),
            endsWith('not in the app yet → "soon" snackbar'),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
    });
  }

  testWidgets('строка бюджета в логе - только id и вид, без названия', (
    tester,
  ) async {
    final h = await ProfileHarness.start(tester);
    await h.openProfile();

    await h.tap(find.text('Семья'));

    final line = h
        .linesOf('profile')
        .singleWhere((l) => l.contains('profile budget tap'));
    expect(
      line,
      endsWith(
        'profile budget tap budgetId=$profileFamilyId kind=shared: not in '
        'the app yet → "soon" snackbar',
      ),
    );
    expect(h.logs.text, isNot(contains('Семья')));
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
  });

  test('«Синхронизировано · …»: только что, минуты, часы, дата', () async {
    await initializeDateFormatting('ru');
    final l10n = lookupAppLocalizations(const Locale('ru'));
    final now = DateTime(2026, 10, 19, 18, 40);

    expect(
      syncedAgo(l10n, now.add(const Duration(seconds: 5)), now),
      'только что',
    );
    expect(
      syncedAgo(l10n, now.subtract(const Duration(seconds: 59)), now),
      'только что',
    );
    expect(
      syncedAgo(l10n, now.subtract(const Duration(minutes: 2)), now),
      '2 мин назад',
    );
    expect(
      syncedAgo(l10n, now.subtract(const Duration(minutes: 59)), now),
      '59 мин назад',
    );
    expect(
      syncedAgo(
        l10n,
        now.subtract(const Duration(hours: 23, minutes: 59)),
        now,
      ),
      '23 ч назад',
    );
    expect(syncedAgo(l10n, DateTime.utc(2026, 10, 17, 9), now), '17 октября');
    expect(syncedAgo(l10n, DateTime(2025, 12, 31, 23), now), '31 декабря 2025');
  });
}
