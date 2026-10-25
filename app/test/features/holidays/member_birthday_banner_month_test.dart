import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/data/db/app_database.dart';
import 'package:milionchik/data/providers.dart';
import 'package:milionchik/data/repositories/prefs_repository.dart';
import 'package:milionchik/features/holidays/mood_controller.dart';
import 'package:milionchik/features/month/month_controller.dart';
import 'package:milionchik/features/month/today_block.dart';
import 'package:milionchik/ui/components/holiday_banner.dart';
import 'package:milionchik/ui/components/month_card.dart';
import 'package:shared/shared.dart';

import '../../support/app_scope.dart';
import '../auth/session_expired_fixture.dart' show testUnmounting;
import '../profile/profile_harness.dart';
import 'member_birthday_fixture.dart';

final class _FailingPrefs implements PrefsRepository {
  _FailingPrefs(this._inner);

  final PrefsRepository _inner;

  @override
  Future<void> setString(String key, String value) async {
    if (key == PrefKeys.hiddenHolidayBanners) {
      throw StateError('disk full (test) key=$key');
    }
    await _inner.setString(key, value);
  }

  @override
  Future<String?> getString(String key) => _inner.getString(key);

  @override
  Future<int?> getInt(String key) => _inner.getInt(key);

  @override
  Future<bool?> getBool(String key) => _inner.getBool(key);

  @override
  Stream<String?> watchString(String key) => _inner.watchString(key);

  @override
  Stream<int?> watchInt(String key) => _inner.watchInt(key);

  @override
  Stream<bool?> watchBool(String key) => _inner.watchBool(key);

  @override
  Future<void> setInt(String key, int value) => _inner.setInt(key, value);

  @override
  Future<void> setBool(String key, bool value) => _inner.setBool(key, value);

  @override
  Future<void> remove(String key) => _inner.remove(key);

  @override
  Future<String> putStringIfAbsent(String key, String Function() create) =>
      _inner.putStringIfAbsent(key, create);
}

const List<String> _secrets = [
  'Дима',
  'Мама',
  'Аня',
  'декабр',
  'ноябр',
  'октябр',
  'MonthDay(',
  'UpcomingBirthday(',
  'Сегодня день рождения',
  'день рождения через',
];

String _two(int v) => v.toString().padLeft(2, '0');

void _expectNoBirthdayInLogs(
  ProfileHarness h,
  DateTime now,
  List<MonthDay> birthdays,
) {
  final text = h.logs.text;
  final secrets = [
    ..._secrets,
    for (final b in birthdays)
      if (b.month != now.month || b.day != now.day) ...[
        '-${_two(b.month)}-${_two(b.day)}',
        '${_two(b.day)}.${_two(b.month)}',
      ],
  ];
  for (final secret in secrets) {
    expect(text, isNot(contains(secret)), reason: '"$secret" in logs');
  }
  for (final line in h.logs.lines) {
    if (line.contains('member birthday')) {
      expect(line, isNot(contains('stage=')), reason: line);
      expect(line, isNot(contains('daysUntil')), reason: line);
      expect(line, isNot(contains(':2026')), reason: line);
      expect(line, isNot(contains(':2027')), reason: line);
      expect(line, isNot(contains('today')), reason: line);
    }
  }
}

Future<void> _restart(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(Duration.zero);
}

Future<String?> _stored(WidgetTester tester, AppDatabase db) =>
    tester.runAsync<String?>(
      () => DriftPrefsRepository(db).getString(PrefKeys.hiddenHolidayBanners),
    );

Future<void> _tapClose(WidgetTester tester, Finder banner) async {
  await tester.runAsync(() async {
    await tester.tap(
      find.descendant(
        of: banner,
        matching: find.byWidgetPredicate((w) => w is InkResponse),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });
  await tester.pumpAndSettle();
}

Rect _rectOf(WidgetTester tester, Finder finder) => tester.getRect(finder);

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testUnmounting('ДР участника через 3 дня (макет 35:11612): плашка '
      '«Участник» над карточкой месяца - аватар, имя без склонения, дата и '
      'бюджет; настроение остаётся сезонным; debug-лог только с userId', (
    tester,
  ) async {
    final db = openTestDatabase();
    await tester.runAsync(
      () => seedMemberBirthdays(db, dima: dimaMockupBirthday),
    );

    final h = await startMemberBirthdayApp(tester, db: db, now: mockupNow);

    final banners = shownMemberBanners(tester);
    expect(banners, hasLength(1));
    final banner = banners.single;
    expect(banner.title, '🎂 Дима — день рождения через 3 дня');
    expect(banner.subtitle, '2 декабря · бюджет «Семья»');
    expect(banner.avatarLetter, 'Д');
    expect(banner.avatarColor, CategoryColor.green);
    expect(banner.onClose, isNotNull);
    expect(holidayBanners, findsNothing);

    final bannerRect = _rectOf(tester, memberBanners);
    final cardRect = _rectOf(tester, find.byType(MonthCard));
    expect(cardRect.top - bannerRect.bottom, 14);
    expect(tester.getTopLeft(find.byType(TodayBlock)).dy - cardRect.bottom, 14);

    final mood = h.container.read(moodControllerProvider);
    expect(mood.mood, Mood.autumn);
    expect(mood.reason, MoodReason.season);
    expect(mood.holiday, isNull);

    expect(
      h.linesOf('holidays', Level.FINE),
      contains(
        endsWith(
          'DEBUG [holidays] member birthday banner shown '
          'userId=$dimaId budgetId=$familyId',
        ),
      ),
    );
    _expectNoBirthdayInLogs(h, mockupNow, [dimaMockupBirthday]);
  });

  testUnmounting('окно 0–7 дней: через 1, 2 и 7 дней - плашка с числом '
      'дней, через 8 дней и на следующий день после ДР - плашки нет', (
    tester,
  ) async {
    final db = openTestDatabase();
    await tester.runAsync(
      () => seedMemberBirthdays(db, dima: dimaMockupBirthday),
    );

    for (final (now, title) in [
      (DateTime(2026, 12, 1, 9), '🎂 Дима — день рождения через 1 день'),
      (DateTime(2026, 11, 30, 9), '🎂 Дима — день рождения через 2 дня'),
      (DateTime(2026, 11, 25, 9), '🎂 Дима — день рождения через 7 дней'),
      (DateTime(2026, 11, 24, 23, 59), null),
      (DateTime(2026, 12, 3, 0, 1), null),
    ]) {
      final h = await startMemberBirthdayApp(tester, db: db, now: now);
      final banners = shownMemberBanners(tester);
      if (title == null) {
        expect(banners, isEmpty, reason: '$now');
      } else {
        expect(banners.map((b) => b.title), [title], reason: '$now');
        expect(banners.single.subtitle, '2 декабря · бюджет «Семья»');
      }
      _expectNoBirthdayInLogs(h, now, [dimaMockupBirthday]);
      await _restart(tester);
    }
  });

  testUnmounting('в день рождения: «🎂 Сегодня день рождения: Дима», '
      'настроение не меняется', (tester) async {
    final db = openTestDatabase();
    await tester.runAsync(
      () => seedMemberBirthdays(db, dima: dimaMockupBirthday),
    );

    final h = await startMemberBirthdayApp(
      tester,
      db: db,
      now: DateTime(2026, 12, 2, 8),
    );

    final banner = shownMemberBanners(tester).single;
    expect(banner.title, '🎂 Сегодня день рождения: Дима');
    expect(banner.subtitle, '2 декабря · бюджет «Семья»');
    expect(h.container.read(moodControllerProvider).mood, Mood.winter);
    expect(holidayBanners, findsNothing);
    _expectNoBirthdayInLogs(h, DateTime(2026, 12, 2, 8), [dimaMockupBirthday]);
  });

  testUnmounting('несколько участников: две плашки, ближайший день рождения '
      'первым; свой день рождения из профиля участника - не плашка '
      '«Участник»', (tester) async {
    final db = openTestDatabase();
    await tester.runAsync(
      () => seedMemberBirthdays(
        db,
        dima: dimaMockupBirthday,
        mama: MonthDay(11, 29),
        self: MonthDay(12, 1),
      ),
    );

    final h = await startMemberBirthdayApp(tester, db: db, now: mockupNow);

    final banners = shownMemberBanners(tester);
    expect(banners.map((b) => b.title), [
      '🎂 Сегодня день рождения: Мама',
      '🎂 Дима — день рождения через 3 дня',
    ]);
    expect(banners.map((b) => b.avatarColor), [
      CategoryColor.pink,
      CategoryColor.green,
    ]);
    expect(banners.map((b) => b.subtitle), [
      '29 ноября · бюджет «Семья»',
      '2 декабря · бюджет «Семья»',
    ]);
    final first = _rectOf(tester, memberBanners.first);
    final second = _rectOf(tester, memberBanners.last);
    expect(second.top - first.bottom, 14);
    expect(_rectOf(tester, find.byType(MonthCard)).top - second.bottom, 14);
    expect(
      h
          .linesOf('holidays', Level.FINE)
          .where((l) => l.contains('member birthday banner shown')),
      [
        endsWith('userId=$mamaId budgetId=$familyId'),
        endsWith('userId=$dimaId budgetId=$familyId'),
      ],
    );
    _expectNoBirthdayInLogs(h, mockupNow, [
      dimaMockupBirthday,
      MonthDay(11, 29),
      MonthDay(12, 1),
    ]);
  });

  testUnmounting('выключены «Дни рождения» или все праздники - плашек '
      '«Участник» нет; выключен другой праздник - плашка есть', (tester) async {
    final db = openTestDatabase();
    await tester.runAsync(
      () => seedMemberBirthdays(
        db,
        dima: dimaMockupBirthday,
        mama: MonthDay(11, 29),
      ),
    );

    for (final (settings, count) in [
      (HolidaySettings(disabled: {HolidayKey.birthday}), 0),
      (const HolidaySettings(enabled: false), 0),
      (
        HolidaySettings(
          enabled: false,
          disabled: {HolidayKey.birthday},
          birthday: MonthDay(5, 5),
        ),
        0,
      ),
      (HolidaySettings(disabled: {HolidayKey.newyear}), 2),
    ]) {
      await startMemberBirthdayApp(
        tester,
        db: db,
        now: mockupNow,
        settings: settings,
      );
      expect(memberBanners, findsNWidgets(count), reason: '$settings');
      await _restart(tester);
    }
  });

  testUnmounting('открыт личный бюджет - плашки нет; переключились на '
      '«Семья» - плашка появилась без перезапуска', (tester) async {
    final db = openTestDatabase();
    await tester.runAsync(
      () => seedMemberBirthdays(
        db,
        dima: dimaMockupBirthday,
        selectFamily: false,
      ),
    );

    final h = await startMemberBirthdayApp(tester, db: db, now: mockupNow);
    expect(find.byType(MonthCard), findsOneWidget);
    expect(memberBanners, findsNothing);

    await tester.runAsync(
      () => h.container
          .read(budgetSelectionProvider.notifier)
          .select(familyId, from: null, by: 'test'),
    );
    await h.settle();

    expect(
      shownMemberBanners(tester).single.title,
      '🎂 Дима — день рождения через 3 дня',
    );
  });

  testUnmounting('другой месяц на главной - плашки нет, вернулись к текущему '
      '- снова есть', (tester) async {
    final db = openTestDatabase();
    await tester.runAsync(
      () => seedMemberBirthdays(db, dima: dimaMockupBirthday),
    );

    final h = await startMemberBirthdayApp(tester, db: db, now: mockupNow);
    expect(memberBanners, findsOneWidget);

    h.container
        .read(monthControllerProvider.notifier)
        .previous(MonthStepSource.arrow);
    await h.settle();
    expect(memberBanners, findsNothing);

    h.container
        .read(monthControllerProvider.notifier)
        .next(MonthStepSource.arrow);
    await h.settle();
    expect(memberBanners, findsOneWidget);
  });

  testUnmounting('под праздничной: Хеллоуин 28.10 и ДР Димы 30.10 - сверху '
      'плашка Хеллоуина, под ней «Участник», настроение - Хеллоуин', (
    tester,
  ) async {
    final db = openTestDatabase();
    await tester.runAsync(
      () => seedMemberBirthdays(db, dima: MonthDay(10, 30)),
    );

    final h = await startMemberBirthdayApp(
      tester,
      db: db,
      now: DateTime(2026, 10, 28, 12),
    );

    final holiday = tester.widget<HolidayBanner>(holidayBanners);
    expect(holiday.title, 'До Хеллоуина 3 дня');
    final member = shownMemberBanners(tester).single;
    expect(member.title, '🎂 Дима — день рождения через 2 дня');
    expect(member.subtitle, '30 октября · бюджет «Семья»');
    final top = _rectOf(tester, holidayBanners);
    final below = _rectOf(tester, memberBanners);
    final card = _rectOf(tester, find.byType(MonthCard));
    expect(below.top - top.bottom, 14);
    expect(card.top - below.bottom, 14);
    expect(h.container.read(moodControllerProvider).mood, Mood.halloween);
    _expectNoBirthdayInLogs(h, DateTime(2026, 10, 28, 12), [MonthDay(10, 30)]);
  });

  testUnmounting('крестик: плашка Димы скрыта до его следующего дня '
      'рождения (ключ участник+год), плашка Мамы осталась; после перезапуска '
      'скрыта, через год снова видна; в логах ни года, ни даты', (
    tester,
  ) async {
    final db = openTestDatabase();
    await tester.runAsync(
      () => seedMemberBirthdays(
        db,
        dima: dimaMockupBirthday,
        mama: MonthDay(11, 29),
      ),
    );

    var h = await startMemberBirthdayApp(tester, db: db, now: mockupNow);
    expect(memberBanners, findsNWidgets(2));

    await _tapClose(tester, memberBanners.last);

    expect(shownMemberBanners(tester).map((b) => b.title), [
      '🎂 Сегодня день рождения: Мама',
    ]);
    expect(await _stored(tester, db), '["member:$dimaId:2026"]');
    expect(
      h.linesOf('holidays', Level.INFO),
      contains(
        matches(
          r'INFO  \[holidays\] member birthday banner hidden '
          'userId=$dimaId'
          r" → until the member's next birthday; saved "
          r'key=hiddenHolidayBanners ids=\[member:'
          '$dimaId'
          r'\] in \d+ms$',
        ),
      ),
    );
    expect(
      h.linesOf('holidays', Level.FINE),
      contains(
        endsWith(
          'member birthday banner close tap userId=$dimaId '
          'budgetId=$familyId',
        ),
      ),
    );
    _expectNoBirthdayInLogs(h, mockupNow, [
      dimaMockupBirthday,
      MonthDay(11, 29),
    ]);

    await _restart(tester);
    h = await startMemberBirthdayApp(
      tester,
      db: db,
      now: DateTime(2026, 12, 2, 9),
    );
    expect(memberBanners, findsNothing);
    expect(
      h.linesOf('holidays', Level.FINE),
      contains(
        endsWith(
          'member birthday banner userId=$dimaId budgetId=$familyId not '
          'shown: closed earlier on this phone',
        ),
      ),
    );
    _expectNoBirthdayInLogs(h, DateTime(2026, 12, 2, 9), [
      dimaMockupBirthday,
      MonthDay(11, 29),
    ]);

    await _restart(tester);
    h = await startMemberBirthdayApp(
      tester,
      db: db,
      now: DateTime(2027, 11, 29, 9),
    );
    expect(shownMemberBanners(tester).map((b) => b.title), [
      '🎂 Сегодня день рождения: Мама',
      '🎂 Дима — день рождения через 3 дня',
    ]);

    await _tapClose(tester, memberBanners.last);
    expect(await _stored(tester, db), '["member:$dimaId:2027"]');
    expect(
      h.linesOf('holidays', Level.INFO),
      contains(
        contains('ids=[member:$dimaId] dropped past=[member:$dimaId] in '),
      ),
    );
    _expectNoBirthdayInLogs(h, DateTime(2027, 11, 29, 9), [
      dimaMockupBirthday,
      MonthDay(11, 29),
    ]);
  });

  testUnmounting('крестик, запись не удалась: плашка скрыта до перезапуска, '
      'warn с ключом и ошибкой, без даты', (tester) async {
    final db = openTestDatabase();
    await tester.runAsync(
      () => seedMemberBirthdays(db, dima: dimaMockupBirthday),
    );

    final h = await startMemberBirthdayApp(
      tester,
      db: db,
      now: mockupNow,
      overrides: [
        prefsRepositoryProvider.overrideWithValue(
          _FailingPrefs(DriftPrefsRepository(db)),
        ),
      ],
    );

    await _tapClose(tester, memberBanners);

    expect(memberBanners, findsNothing);
    expect(await _stored(tester, db), isNull);
    expect(
      h.linesOf('holidays', Level.WARNING),
      contains(
        matches(
          r'WARN  \[holidays\] member birthday banner hidden '
          'userId=$dimaId'
          r' for this run only: saving key=hiddenHolidayBanners failed after '
          r'\d+ms → shown again after restart: StateError',
        ),
      ),
    );
    _expectNoBirthdayInLogs(h, mockupNow, [dimaMockupBirthday]);
  });
}
