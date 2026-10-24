import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/core/clock.dart';
import 'package:milionchik/data/db/app_database.dart';
import 'package:milionchik/data/holiday_settings.dart';
import 'package:milionchik/data/providers.dart';
import 'package:milionchik/data/session/session.dart';
import 'package:milionchik/data/session/session_providers.dart';
import 'package:milionchik/data/session/session_state.dart';
import 'package:milionchik/features/holidays/mood_controller.dart';
import 'package:shared/shared.dart';

import '../../data/api/fake_api_adapter.dart';
import '../../data/sync/sync_triggers_fixture.dart';

const _user = SessionUser(
  userId: 'user-mood-77',
  login: 'mood_user',
  displayName: 'Настя',
);

User _account({
  bool enabled = true,
  Set<String> disabled = const {},
  MonthDay? birthday,
}) => User(
  id: _user.userId,
  login: _user.login,
  displayName: _user.displayName,
  birthday: birthday,
  holidaysEnabled: enabled,
  holidaysDisabled: disabled,
  createdAt: DateTime.utc(2026, 10, 1),
);

void main() {
  late LogCapture logs;
  late AppDatabase db;
  late VirtualTime time;
  late DateTime start;
  late Duration shift;

  setUp(() {
    logs = LogCapture();
    db = AppDatabase.memory();
    time = VirtualTime();
    shift = Duration.zero;
  });

  tearDown(() async {
    await logs.dispose();
    await db.close();
  });

  DateTime now() => start.add(time.now).add(shift);

  ProviderContainer container({
    CachedHolidaySettings? cached,
    bool signedIn = true,
    Clock Function(Ref ref)? clock,
  }) {
    final c = ProviderContainer.test(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        clockProvider.overrideWith(clock ?? (ref) => Clock(now: now)),
        moodTimerProvider.overrideWithValue(time.start),
        if (signedIn)
          sessionProvider.overrideWithBuild(
            (ref, _) => const SessionActive(_user),
          ),
        if (cached != null)
          startupHolidaySettingsProvider.overrideWithValue(cached),
      ],
    );
    c.listen(moodControllerProvider, (_, _) {});
    return c;
  }

  List<String> moodInfo() => logs.linesOf('mood', Level.INFO);

  Duration activeDelay() => time.active.single.delay;

  test('старт 31.10 в 18:40: Хеллоуин в «день», info с датой, причиной и '
      'поводом startup; таймер до полуночи 5 ч 20 мин', () async {
    start = DateTime(2026, 10, 31, 18, 40);
    final c = container();

    final mood = c.read(moodControllerProvider);

    expect(mood.mood, Mood.halloween);
    expect(mood.reason, MoodReason.holiday);
    expect(mood.holiday!.stage, HolidayStage.day);
    expect(moodInfo(), [
      endsWith(
        'INFO  [mood] mood recalculated trigger=startup date=2026-10-31 '
        'mood=halloween reason=holiday holiday=halloween stage=day '
        'daysUntilDay=0 settings=HolidaySettings(enabled: true, '
        'disabled: [], birthday: none)',
      ),
    ]);
    expect(activeDelay(), const Duration(hours: 5, minutes: 20));
    expect(c.read(moodControllerProvider.notifier).midnightScheduled, isTrue);
  });

  test('полночь 31.10 → 1.11 без перезапуска: Хеллоуин сменяется осенью, '
      'повод midnight, следующий таймер на сутки', () async {
    start = DateTime(2026, 10, 31, 23, 59, 50);
    final c = container();
    final seen = <Mood>[];
    c.listen(moodControllerProvider, (_, next) => seen.add(next.mood));
    expect(activeDelay(), const Duration(seconds: 10));

    await time.elapse(const Duration(seconds: 9));
    expect(c.read(moodControllerProvider).mood, Mood.halloween);

    await time.elapse(const Duration(seconds: 1));

    final mood = c.read(moodControllerProvider);
    expect(mood.date, LocalDate(2026, 11, 1));
    expect(mood.mood, Mood.autumn);
    expect(mood.reason, MoodReason.season);
    expect(seen, [Mood.autumn]);
    expect(
      moodInfo().last,
      endsWith(
        'mood recalculated trigger=midnight date=2026-11-01 mood=autumn '
        'reason=season settings=HolidaySettings(enabled: true, disabled: [], '
        'birthday: none) (was halloween on 2026-10-31)',
      ),
    );
    expect(activeDelay(), const Duration(hours: 24));
  });

  test('таймер сработал до полуночи (часы перевели назад на час): пересчёта '
      'нет, таймер заново; в настоящую полночь - осень', () async {
    start = DateTime(2026, 10, 31, 23, 59, 30);
    final c = container();
    shift = const Duration(hours: -1);

    await time.elapse(const Duration(seconds: 30));

    expect(c.read(moodControllerProvider).mood, Mood.halloween);
    expect(moodInfo(), hasLength(1));
    expect(
      logs.linesOf('mood', Level.FINE),
      contains(
        endsWith('mood midnight timer fired, still 2026-10-31: rescheduling'),
      ),
    );
    expect(activeDelay(), const Duration(hours: 1));

    await time.elapse(const Duration(hours: 1));
    expect(c.read(moodControllerProvider).mood, Mood.autumn);
  });

  test('часовой пояс: ночью перелёт +3 ч, приложение в фоне, таймер ещё не '
      'сработал - при возвращении сразу 1 ноября, повод app resumed', () async {
    start = DateTime(2026, 10, 31, 22);
    final c = container();
    expect(activeDelay(), const Duration(hours: 2));

    await time.elapse(const Duration(minutes: 10));
    shift = const Duration(hours: 3);
    c.read(moodControllerProvider.notifier).resumed();

    final mood = c.read(moodControllerProvider);
    expect(mood.date, LocalDate(2026, 11, 1));
    expect(mood.mood, Mood.autumn);
    expect(
      moodInfo().last,
      contains(
        'mood recalculated trigger=app resumed date=2026-11-01 mood=autumn',
      ),
    );
    expect(activeDelay(), const Duration(hours: 22, minutes: 50));
  });

  test('возвращение в тот же день: настроение прежнее, info нет, таймер '
      'переставлен', () async {
    start = DateTime(2026, 10, 27, 9);
    final c = container();

    await time.elapse(const Duration(hours: 3));
    c.read(moodControllerProvider.notifier).resumed();

    expect(c.read(moodControllerProvider).mood, Mood.halloween);
    expect(moodInfo(), hasLength(1));
    expect(
      logs.linesOf('mood', Level.FINE),
      contains(
        endsWith(
          'app resumed, still 2026-10-27: mood=halloween kept, midnight timer '
          'reset',
        ),
      ),
    );
    expect(activeDelay(), const Duration(hours: 12));
  });

  test('переход года: 31.12 → 1.01 Новый год остаётся, наступает «день»; '
      '8.01 → 9.01 - зима', () async {
    start = DateTime(2026, 12, 31, 23, 59);
    final c = container();
    expect(c.read(moodControllerProvider).holiday!.stage, HolidayStage.before);

    await time.elapse(const Duration(minutes: 1));

    final newYear = c.read(moodControllerProvider);
    expect(newYear.date, LocalDate(2027, 1, 1));
    expect(newYear.mood, Mood.newyear);
    expect(newYear.holiday!.stage, HolidayStage.day);
    expect(moodInfo().last, endsWith('(unchanged)'));

    await time.elapse(const Duration(days: 8));

    final winter = c.read(moodControllerProvider);
    expect(winter.date, LocalDate(2027, 1, 9));
    expect(winter.mood, Mood.winter);
    expect(
      moodInfo().last,
      contains('trigger=midnight date=2027-01-09 mood=winter reason=season'),
    );
  });

  test('високосный год: ДР 29 февраля - 28.02.2028 «до», в полночь «день» '
      '29.02, ещё через полночь - весна; в логе причина без даты ДР', () async {
    start = DateTime(2028, 2, 28, 23, 59, 50);
    final c = container(
      cached: CachedHolidaySettings(
        userId: _user.userId,
        settings: HolidaySettings(birthday: MonthDay(2, 29)),
      ),
    );
    final before = c.read(moodControllerProvider);
    expect(before.mood, Mood.birthday);
    expect(before.holiday!.stage, HolidayStage.before);

    await time.elapse(const Duration(seconds: 10));
    final day = c.read(moodControllerProvider);
    expect(day.date, LocalDate(2028, 2, 29));
    expect(day.holiday!.stage, HolidayStage.day);

    await time.elapse(const Duration(days: 1));
    expect(c.read(moodControllerProvider).mood, Mood.spring);

    final birthdayLines = [
      for (final line in moodInfo())
        if (line.contains('reason=birthday')) line,
    ];
    expect(birthdayLines, hasLength(2));
    for (final line in birthdayLines) {
      expect(line, contains('birthday: set'));
      expect(line, isNot(contains('daysUntilDay')));
      expect(line, isNot(contains('2/29')));
    }
  });

  test('смена настроек праздников (ответ /me): пересчёт сразу, повод '
      'holiday settings changed; выключены все - причина off', () async {
    start = DateTime(2026, 10, 31, 12);
    final c = container(
      cached: CachedHolidaySettings(
        userId: _user.userId,
        settings: const HolidaySettings(),
      ),
    );
    expect(c.read(moodControllerProvider).mood, Mood.halloween);

    final settings = c.read(accountHolidaySettingsProvider.notifier);
    expect(
      await settings.apply(_account(enabled: false), source: 'test'),
      isTrue,
    );

    final off = c.read(moodControllerProvider);
    expect(off.mood, Mood.autumn);
    expect(off.reason, MoodReason.off);
    expect(
      moodInfo().last,
      endsWith(
        'mood recalculated trigger=holiday settings changed date=2026-10-31 '
        'mood=autumn reason=off (holidays turned off) skipped=[halloween] '
        'settings=HolidaySettings(enabled: false, disabled: [], birthday: '
        'none) (was halloween on 2026-10-31)',
      ),
    );

    await settings.apply(_account(disabled: {'halloween'}), source: 'test');
    final season = c.read(moodControllerProvider);
    expect(season.mood, Mood.autumn);
    expect(season.reason, MoodReason.season);
    expect(moodInfo().last, contains('reason=season skipped=[halloween]'));

    await settings.apply(_account(), source: 'test');
    expect(c.read(moodControllerProvider).mood, Mood.halloween);
    expect(moodInfo(), hasLength(4));
  });

  test('подмена «сегодня» (debug): 31 октября - Хеллоуин, 1 ноября - осень, '
      'повод today override changed', () async {
    start = DateTime(2026, 10, 20, 15);
    final c = container(
      clock: (ref) {
        final day = ref.watch(todayOverrideProvider);
        return day == null
            ? Clock(now: now)
            : Clock(now: () => DateTime(day.year, day.month, day.day, 15));
      },
    );
    expect(c.read(moodControllerProvider).mood, Mood.autumn);

    expect(
      await c.read(todayOverrideProvider.notifier).set(LocalDate(2026, 10, 31)),
      isTrue,
    );
    expect(c.read(moodControllerProvider).mood, Mood.halloween);
    expect(
      moodInfo().last,
      contains(
        'trigger=today override changed date=2026-10-31 mood=halloween '
        'reason=holiday holiday=halloween stage=day',
      ),
    );

    await c.read(todayOverrideProvider.notifier).set(LocalDate(2026, 11, 1));
    expect(c.read(moodControllerProvider).mood, Mood.autumn);
    expect(
      moodInfo().last,
      contains('trigger=today override changed date=2026-11-01 mood=autumn'),
    );
    expect(activeDelay(), const Duration(hours: 9));
  });

  test('без входа - настройки по умолчанию; контейнер закрыт - таймер на '
      'полночь снят', () async {
    start = DateTime(2026, 10, 25, 8);
    final c = container(signedIn: false);
    expect(c.read(moodControllerProvider).mood, Mood.halloween);
    expect(c.read(moodControllerProvider).settings, const HolidaySettings());
    expect(time.active, hasLength(1));

    c.dispose();

    expect(time.active, isEmpty);
  });
}
