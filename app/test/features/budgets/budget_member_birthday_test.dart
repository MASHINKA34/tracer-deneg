import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milionchik/features/budgets/budget_screen.dart';
import 'package:milionchik/features/budgets/budget_screen_view.dart';
import 'package:shared/shared.dart';

import '../../support/app_scope.dart';
import '../auth/session_expired_fixture.dart' show testUnmounting;
import '../holidays/member_birthday_fixture.dart';
import '../profile/profile_fixture.dart';
import '../profile/profile_harness.dart';

BudgetMemberRow _row(WidgetTester tester, String userId) =>
    tester.widget<BudgetMemberRow>(find.byKey(ValueKey('member-$userId')));

Future<ProfileHarness> _openFamily(
  WidgetTester tester, {
  required DateTime now,
  MonthDay? dima,
  MonthDay? mama,
  MonthDay? self,
  HolidaySettings settings = const HolidaySettings(),
}) async {
  final db = openTestDatabase();
  await tester.runAsync(
    () => seedMemberBirthdays(
      db,
      dima: dima,
      mama: mama,
      self: self,
      selectFamily: false,
      expenses: true,
    ),
  );
  final h = await startMemberBirthdayApp(
    tester,
    db: db,
    now: now,
    settings: settings,
  );
  await h.openProfile();
  await h.tap(find.text('Семья').last);
  expect(find.byType(BudgetScreen), findsOneWidget);
  return h;
}

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testUnmounting('список участников: ДР Димы через 3 дня - «Дима 🎂», '
      'подпись роли та же; у Мамы без ДР и у себя (ДР через 2 дня) - без 🎂', (
    tester,
  ) async {
    final h = await _openFamily(
      tester,
      now: mockupNow,
      dima: dimaMockupBirthday,
      self: MonthDay(12, 1),
    );

    final dima = _row(tester, dimaId);
    expect(dima.name, 'Дима 🎂');
    expect(dima.plainName, 'Дима');
    expect(dima.subtitle, 'Участник · с 2 октября');
    expect(find.text('Дима 🎂'), findsOneWidget);
    expect(_row(tester, mamaId).name, 'Мама');
    expect(_row(tester, profileUserId).name, 'Аня (ты)');
    expect(find.bySemanticsLabel('Дима 🎂, Участник · с 2 октября'), findsOne);
    expect(h.logs.text, isNot(contains('Дима')));
  });

  testUnmounting('окно 0–7 дней в списке: сегодня и через 7 дней - 🎂, через '
      '8 дней и вчера - нет', (tester) async {
    for (final (now, dimaName, mamaName) in [
      (DateTime(2026, 11, 25, 9), 'Дима 🎂', 'Мама 🎂'),
      (DateTime(2026, 11, 24, 9), 'Дима', 'Мама 🎂'),
      (DateTime(2026, 12, 2, 9), 'Дима 🎂', 'Мама'),
      (DateTime(2026, 11, 30, 9), 'Дима 🎂', 'Мама'),
      (DateTime(2026, 11, 29, 9), 'Дима 🎂', 'Мама 🎂'),
    ]) {
      await _openFamily(
        tester,
        now: now,
        dima: dimaMockupBirthday,
        mama: MonthDay(11, 29),
      );
      expect(_row(tester, dimaId).name, dimaName, reason: '$now');
      expect(_row(tester, mamaId).name, mamaName, reason: '$now');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(Duration.zero);
    }
  });

  testUnmounting('выключены «Дни рождения» или все праздники - 🎂 в списке '
      'нет', (tester) async {
    for (final settings in [
      HolidaySettings(disabled: {HolidayKey.birthday}),
      const HolidaySettings(enabled: false),
    ]) {
      await _openFamily(
        tester,
        now: mockupNow,
        dima: dimaMockupBirthday,
        mama: MonthDay(11, 29),
        settings: settings,
      );
      expect(_row(tester, dimaId).name, 'Дима', reason: '$settings');
      expect(_row(tester, mamaId).name, 'Мама', reason: '$settings');
      expect(find.textContaining('🎂'), findsNothing, reason: '$settings');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(Duration.zero);
    }
  });
}
