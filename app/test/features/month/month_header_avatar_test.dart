import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/data/repositories/members_repository.dart';
import 'package:milionchik/features/month/month_header.dart';
import 'package:milionchik/features/profile/profile_account_card.dart';
import 'package:milionchik/ui/components/avatar.dart';
import 'package:shared/shared.dart';

import '../../support/app_scope.dart';
import '../profile/profile_fixture.dart';
import '../profile/profile_harness.dart';
import '../shell/shell_harness.dart';

AppAvatar _avatarIn(WidgetTester tester, Type parent) =>
    tester.widget<AppAvatar>(
      find.descendant(
        of: find.byType(parent),
        matching: find.byType(AppAvatar),
      ),
    );

void main() {
  testWidgets('после входа в шапке буква имени и цвет участника, как в '
      'карточке профиля, а не буква бюджета', (tester) async {
    final h = await ProfileHarness.start(tester);
    await tester.runAsync(
      () => DriftMembersRepository(h.db).applyProfilesFromServer(const [
        MemberProfile(
          userId: profileUserId,
          displayName: 'Аня',
          avatarColor: CategoryColor.pink,
        ),
      ]),
    );
    await h.settle();

    expect(
      find.descendant(
        of: find.byType(MonthHeaderView),
        matching: find.text('Личный бюджет'),
      ),
      findsOneWidget,
    );
    final header = _avatarIn(tester, MonthHeaderView);
    expect(header.letter, 'А');
    expect(header.color, CategoryColor.pink);
    expect(
      h.linesOf('month', Level.FINE),
      contains(
        endsWith(
          'header avatar userId=$profileUserId: letter of the user name '
          'from member profile, color=pink',
        ),
      ),
    );

    await h.openProfile();
    final profile = _avatarIn(tester, ProfileAccountCard);
    expect(profile.letter, header.letter);
    expect(profile.color, header.color);
  });

  testWidgets('сессия есть, профиля участника ещё нет: буква имени из сессии '
      'и синий, как в профиле', (tester) async {
    final h = await ProfileHarness.start(tester, seed: false);

    final header = _avatarIn(tester, MonthHeaderView);
    expect(header.letter, 'А');
    expect(header.color, CategoryColor.blue);
    expect(
      h.linesOf('month', Level.FINE),
      contains(
        endsWith(
          'header avatar userId=$profileUserId: letter of the user name '
          'from session (no member profile yet), color=blue',
        ),
      ),
    );

    await h.openProfile();
    final profile = _avatarIn(tester, ProfileAccountCard);
    expect(profile.letter, header.letter);
    expect(profile.color, header.color);
  });

  testWidgets('без сессии (демо-данные) — буква названия бюджета и синий', (
    tester,
  ) async {
    final db = openTestDatabase();
    await testBudgets(db).createLocalPersonal();
    final h = await ShellHarness.start(tester, db: db);

    final header = _avatarIn(tester, MonthHeaderView);
    expect(header.letter, 'Л');
    expect(header.color, CategoryColor.blue);
    expect(
      h.records
          .where((r) => r.loggerName == 'month' && r.level == Level.FINE)
          .map((r) => r.message),
      contains(
        'header avatar: no session → letter of the budget name, color=blue',
      ),
    );
  });
}
