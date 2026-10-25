import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:milionchik/data/db/app_database.dart';
import 'package:milionchik/data/holiday_settings.dart';
import 'package:milionchik/data/repositories/members_repository.dart';
import 'package:milionchik/data/repositories/prefs_repository.dart';
import 'package:milionchik/ui/components/holiday_banner.dart';
import 'package:shared/shared.dart';

import '../../data/api/fake_api_adapter.dart';
import '../budgets/budget_screen_fixture.dart';
import '../profile/profile_fixture.dart';
import '../profile/profile_harness.dart';

export '../budgets/budget_screen_fixture.dart' show dimaId, familyId, mamaId;

final DateTime mockupNow = DateTime(2026, 11, 29, 18, 40);

final MonthDay dimaMockupBirthday = MonthDay(12, 2);

Future<void> seedMemberBirthdays(
  AppDatabase db, {
  MonthDay? dima,
  MonthDay? mama,
  MonthDay? self,
  bool selectFamily = true,
  bool expenses = false,
}) async {
  await BudgetScreenFixture.seed(db, owner: true, expenses: expenses);
  await DriftMembersRepository(db).applyProfilesFromServer([
    MemberProfile(
      userId: dimaId,
      displayName: 'Дима',
      avatarColor: CategoryColor.green,
      birthday: dima,
    ),
    MemberProfile(
      userId: mamaId,
      displayName: 'Мама',
      avatarColor: CategoryColor.pink,
      birthday: mama,
    ),
    if (self != null)
      MemberProfile(
        userId: profileUserId,
        displayName: 'Аня',
        avatarColor: CategoryColor.blue,
        birthday: self,
      ),
  ]);
  if (selectFamily) {
    await DriftPrefsRepository(db)
        .setString(PrefKeys.selectedBudgetId, familyId);
  }
}

FakeReply memberBirthdayServer(FakeCall call) {
  if (call.method == 'GET' && call.path.endsWith('/sync/pull')) {
    final cursor = int.parse(call.options.uri.queryParameters['cursor']!);
    return FakeReply.json(
      200,
      SyncPullResponse(cursor: cursor, hasMore: false).toJson(),
    );
  }
  return FakeReply.error(503, 'unavailable', 'нет сервера (тест)');
}

Future<ProfileHarness> startMemberBirthdayApp(
  WidgetTester tester, {
  required AppDatabase db,
  required DateTime now,
  HolidaySettings settings = const HolidaySettings(),
  Size size = const Size(360, 800),
  double textScale = 1,
  Brightness brightness = Brightness.light,
  List<Override> overrides = const [],
}) async {
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  return ProfileHarness.start(
    tester,
    server: memberBirthdayServer,
    seed: false,
    db: db,
    now: now,
    size: size,
    textScale: textScale,
    platformBrightness: brightness,
    overrides: [
      holidaySettingsProvider.overrideWithValue(settings),
      ...overrides,
    ],
  );
}

Finder get memberBanners => find.byWidgetPredicate(
  (w) => w is HolidayBanner && w.type == HolidayBannerType.member,
);

Finder get holidayBanners => find.byWidgetPredicate(
  (w) => w is HolidayBanner && w.type != HolidayBannerType.member,
);

List<HolidayBanner> shownMemberBanners(WidgetTester tester) =>
    tester.widgetList<HolidayBanner>(memberBanners).toList();
