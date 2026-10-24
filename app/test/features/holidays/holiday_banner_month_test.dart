import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/app.dart';
import 'package:milionchik/core/clock.dart';
import 'package:milionchik/core/data_startup.dart';
import 'package:milionchik/data/current_user.dart';
import 'package:milionchik/data/db/app_database.dart';
import 'package:milionchik/data/dev_seed.dart';
import 'package:milionchik/data/holiday_settings.dart';
import 'package:milionchik/data/providers.dart';
import 'package:milionchik/data/repositories/account_data_cleaner.dart';
import 'package:milionchik/data/repositories/members_repository.dart';
import 'package:milionchik/data/repositories/prefs_repository.dart';
import 'package:milionchik/data/session/session_providers.dart';
import 'package:milionchik/data/session/session_state.dart';
import 'package:milionchik/features/holidays/holiday_banner_controller.dart';
import 'package:milionchik/features/month/month_screen.dart';
import 'package:milionchik/features/month/today_block.dart';
import 'package:milionchik/features/profile/theme_mode.dart';
import 'package:milionchik/ui/components/holiday_banner.dart';
import 'package:milionchik/ui/components/month_card.dart';
import 'package:shared/shared.dart';

import '../../data/api/fake_api_adapter.dart';
import '../../support/app_scope.dart';
import '../../support/test_fonts.dart';
import '../auth/session_expired_fixture.dart' show testUnmounting;
import 'holiday_banner_fixture.dart';

final class _FailingPrefs implements PrefsRepository {
  _FailingPrefs(this._inner);

  final PrefsRepository _inner;

  @override
  Future<void> setString(String key, String value) async {
    if (key == PrefKeys.hiddenHolidayBanners) {
      throw StateError('disk full (test) value=$value');
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

Finder get _banner => find.byType(HolidayBanner);

Finder get _close => find.descendant(
  of: _banner,
  matching: find.byWidgetPredicate((w) => w is InkResponse),
);

Future<String?> _stored(WidgetTester tester, AppDatabase db) async =>
    tester.runAsync<String?>(
      () => DriftPrefsRepository(db).getString(PrefKeys.hiddenHolidayBanners),
    );

Future<void> _tapClose(WidgetTester tester) async {
  await tester.runAsync(() async {
    await tester.tap(_close);
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  late LogCapture logs;
  setUp(() => logs = LogCapture());
  tearDown(() => logs.dispose());

  Future<AppDatabase> startApp(
    WidgetTester tester, {
    required DateTime Function() now,
    ThemeMode themeMode = ThemeMode.light,
    List<Override> overrides = const [],
    AppDatabase? database,
  }) async {
    await loadTestFonts();
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(360, 800);
    addTearDown(tester.view.reset);
    final db = database ?? openTestDatabase();
    if (database == null) {
      await tester.runAsync(() => seedHolidayMonth(db, HolidayKey.halloween));
    }
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          clockProvider.overrideWithValue(Clock(now: now)),
          themeModeProvider.overrideWithBuild((ref, _) => themeMode),
          ...overrides,
        ],
        child: const MilionchikApp(),
      ),
    );
    await tester.pumpAndSettle();
    return db;
  }

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(MonthScreen)));

  testUnmounting('Хеллоуин 28.10: плашка-отсчёт над карточкой текущего '
      'месяца, отступы 14 до карточки и до «Сегодня», показ в debug', (
    tester,
  ) async {
    await startApp(tester, now: () => DateTime(2026, 10, 28, 12));

    expect(_banner, findsOneWidget);
    final banner = tester.widget<HolidayBanner>(_banner);
    expect(banner.type, HolidayBannerType.countdown);
    expect(banner.emoji, '🎃');
    expect(banner.title, 'До Хеллоуина 3 дня');
    expect(banner.subtitle, 'Запасайся конфетами 🍬');

    final bannerRect = tester.getRect(_banner);
    final cardRect = tester.getRect(find.byType(MonthCard));
    final todayTop = tester.getTopLeft(find.byType(TodayBlock)).dy;
    expect(bannerRect.left, 12);
    expect(bannerRect.width, 336);
    expect(bannerRect.height, 62);
    expect(cardRect.top - bannerRect.bottom, 14);
    expect(todayTop - cardRect.bottom, 14);
    expect(
      logs.linesOf('holidays', Level.FINE),
      contains(
        endsWith(
          'holiday banner shown holiday=halloween stage=before '
          'daysUntilDay=3 id=halloween:2026 type=countdown',
        ),
      ),
    );
  });

  testUnmounting('Хеллоуин в тёмной теме - «жуткая» подпись, 31.10 - '
      'поздравление с заливкой', (tester) async {
    var now = DateTime(2026, 10, 28, 12);
    final db = await startApp(
      tester,
      now: () => now,
      themeMode: ThemeMode.dark,
    );

    var banner = tester.widget<HolidayBanner>(_banner);
    expect(banner.subtitle, 'Ночь всё ближе… \u{1F578}️');
    expect(Theme.of(tester.element(_banner)).brightness, Brightness.dark);

    await tester.pumpWidget(const SizedBox.shrink());
    now = DateTime(2026, 10, 31, 12);
    await startApp(
      tester,
      now: () => now,
      themeMode: ThemeMode.dark,
      database: db,
    );

    banner = tester.widget<HolidayBanner>(_banner);
    expect(banner.type, HolidayBannerType.greeting);
    expect(banner.title, 'С Хеллоуином!');
    expect(banner.subtitle, 'Не выключай свет… \u{1F56F}️');
  });

  testUnmounting('не праздник 19.10 - плашки нет, до «Сегодня» как раньше '
      '20; 25.10, первый день Хеллоуина - плашка есть', (tester) async {
    var now = DateTime(2026, 10, 19, 12);
    final db = await startApp(tester, now: () => now);

    expect(_banner, findsNothing);
    final cardRect = tester.getRect(find.byType(MonthCard));
    final todayTop = tester.getTopLeft(find.byType(TodayBlock)).dy;
    expect(todayTop - cardRect.bottom, 20);

    await tester.pumpWidget(const SizedBox.shrink());
    now = DateTime(2026, 10, 25, 12);
    await startApp(tester, now: () => now, database: db);
    expect(tester.widget<HolidayBanner>(_banner).title, 'До Хеллоуина 6 дней');
  });

  testUnmounting('плашка только над текущим месяцем: в сентябре её нет, '
      'вернулись в октябрь - снова есть', (tester) async {
    await startApp(tester, now: () => DateTime(2026, 10, 28, 12));
    expect(_banner, findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Предыдущий месяц'));
    await tester.pumpAndSettle();
    expect(tester.widget<MonthCard>(find.byType(MonthCard)).month.month, 9);
    expect(_banner, findsNothing);

    await tester.tap(find.bySemanticsLabel('Следующий месяц'));
    await tester.pumpAndSettle();
    expect(tester.widget<MonthCard>(find.byType(MonthCard)).month.month, 10);
    expect(_banner, findsOneWidget);
  });

  testUnmounting('праздник выключен в настройках или все праздники '
      'выключены - плашки нет; другой праздник выключен - есть', (
    tester,
  ) async {
    final db = openTestDatabase();
    await tester.runAsync(() => seedHolidayMonth(db, HolidayKey.halloween));
    for (final (settings, shown) in const [
      (HolidaySettings(disabled: {HolidayKey.halloween}), false),
      (HolidaySettings(enabled: false), false),
      (HolidaySettings(disabled: {HolidayKey.newyear}), true),
    ]) {
      await startApp(
        tester,
        now: () => DateTime(2026, 10, 28, 12),
        database: db,
        overrides: [holidaySettingsProvider.overrideWithValue(settings)],
      );
      expect(
        _banner,
        shown ? findsOneWidget : findsNothing,
        reason: '$settings',
      );
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testUnmounting('крестик: плашка исчезает, в local_prefs ключ '
      '«праздник+год», info с ключом', (tester) async {
    final db = await startApp(tester, now: () => DateTime(2026, 10, 28, 12));

    await _tapClose(tester);

    expect(_banner, findsNothing);
    expect(await _stored(tester, db), '["halloween:2026"]');
    expect(
      logs.linesOf('holidays', Level.INFO),
      contains(
        matches(
          r'INFO  \[holidays\] holiday banner hidden id=halloween:2026 '
          r'holiday=halloween stage=before → until the next holiday; saved '
          r'key=hiddenHolidayBanners ids=\[halloween:2026\] in \d+ms$',
        ),
      ),
    );
    final cardRect = tester.getRect(find.byType(MonthCard));
    final todayTop = tester.getTopLeft(find.byType(TodayBlock)).dy;
    expect(todayTop - cardRect.bottom, 20);
  });

  testUnmounting('ключи прошлых лет при записи убираются, этого и '
      'следующего года остаются', (tester) async {
    final db = openTestDatabase();
    await tester.runAsync(() async {
      await seedHolidayMonth(db, HolidayKey.halloween);
      await DriftPrefsRepository(db).setString(
        PrefKeys.hiddenHolidayBanners,
        '["halloween:2025","newyear:2026","newyear:2027"]',
      );
    });
    await startApp(tester, now: () => DateTime(2026, 10, 28, 12), database: db);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();

    await _tapClose(tester);

    expect(
      await _stored(tester, db),
      '["halloween:2026","newyear:2026","newyear:2027"]',
    );
    expect(
      logs.linesOf('holidays', Level.INFO),
      contains(contains('dropped past=[halloween:2025]')),
    );
  });

  testUnmounting('после перезапуска закрытой плашки нет с первого кадра, '
      'а следующий праздник (Новый год 20.12) - с плашкой', (tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(360, 800);
    addTearDown(tester.view.reset);
    final db = AppDatabase.memory();
    await tester.runAsync(
      () =>
          DriftPrefsRepository(db)
              .setString(PrefKeys.todayOverride, '2026-10-28'),
    );

    Future<DataReady> launch() async =>
        (await tester.runAsync(
              () => startData(
                open: () async => db,
                seed: (db) => DevSeed(
                  db,
                  currentUser: LocalPrefsCurrentUser(DriftPrefsRepository(db)),
                ).runIfRequested(flag: 'true', debugBuild: true),
                readSession: () async => null,
                devSeedFlag: 'true',
              ),
            ))!
            as DataReady;

    final first = await launch();
    expect(first.hiddenHolidayBanners, isEmpty);
    await tester.pumpWidget(appRoot(first));
    await tester.pumpAndSettle();
    expect(tester.widget<HolidayBanner>(_banner).title, 'До Хеллоуина 3 дня');
    await _tapClose(tester);
    expect(_banner, findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);

    final second = await launch();
    expect(second.hiddenHolidayBanners, {'halloween:2026'});
    await tester.pumpWidget(appRoot(second));
    await tester.pump();
    await tester.pump();
    expect(find.byType(MonthCard), findsOneWidget);
    expect(_banner, findsNothing);
    await tester.pumpAndSettle();
    expect(_banner, findsNothing);
    expect(
      logs.linesOf('holidays', Level.INFO),
      contains(
        matches(
          r'hidden holiday banners \[halloween:2026\] from '
          r'key=hiddenHolidayBanners in \d+ms$',
        ),
      ),
    );

    await tester.runAsync(
      () =>
          containerOf(tester)
              .read(todayOverrideProvider.notifier)
              .set(LocalDate(2026, 12, 20)),
    );
    await tester.pumpAndSettle();
    final banner = tester.widget<HolidayBanner>(_banner);
    expect(banner.emoji, '🎄');
    expect(banner.title, 'До Нового года 12 дней');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
    await tester.runAsync(db.close);
  });

  testUnmounting('выход из аккаунта стирает закрытые плашки - плашка снова '
      'видна без перезапуска', (tester) async {
    final db = await startApp(tester, now: () => DateTime(2026, 10, 28, 12));
    await _tapClose(tester);
    expect(_banner, findsNothing);

    final cleared = DriftAccountDataCleaner(db).clearAccountData('sign-out');
    await tester.pumpAndSettle();
    expect((await cleared).prefs, contains(PrefKeys.hiddenHolidayBanners));

    expect(await _stored(tester, db), isNull);
    expect(_banner, findsOneWidget);
    expect(
      logs.linesOf('holidays', Level.INFO),
      contains(
        endsWith(
          'hidden holiday banners changed on the phone: [halloween:2026] → '
          '[] (key removed)',
        ),
      ),
    );
  });

  testUnmounting('запись не удалась: плашка скрыта до перезапуска, warn с '
      'ключом и ошибкой', (tester) async {
    final db = openTestDatabase();
    await tester.runAsync(() => seedHolidayMonth(db, HolidayKey.halloween));
    await startApp(
      tester,
      now: () => DateTime(2026, 10, 28, 12),
      database: db,
      overrides: [
        prefsRepositoryProvider.overrideWithValue(
          _FailingPrefs(DriftPrefsRepository(db)),
        ),
      ],
    );

    await _tapClose(tester);

    expect(_banner, findsNothing);
    expect(await _stored(tester, db), isNull);
    expect(
      logs.linesOf('holidays', Level.WARNING),
      contains(
        matches(
          r'WARN  \[holidays\] holiday banner hidden id=halloween:2026 for '
          r'this run only: saving key=hiddenHolidayBanners failed after '
          r'\d+ms → shown again after restart: StateError',
        ),
      ),
    );
  });

  testUnmounting('день рождения: имя аккаунта, свежее из профиля '
      'участника; в логах плашки нет ни имени, ни дней до дня рождения', (
    tester,
  ) async {
    final db = openTestDatabase();
    await tester.runAsync(() => seedHolidayMonth(db, HolidayKey.birthday));
    var now = DateTime(2026, 11, 11, 12);
    await startApp(
      tester,
      now: () => now,
      database: db,
      overrides: [
        sessionProvider.overrideWithBuild(
          (ref, _) => const SessionActive(anya),
        ),
        holidaySettingsProvider.overrideWithValue(
          HolidaySettings(birthday: anyaBirthday),
        ),
      ],
    );

    final banner = tester.widget<HolidayBanner>(_banner);
    expect(banner.emoji, '🎂');
    expect(banner.title, 'До твоего дня рождения 3 дня');
    expect(banner.subtitle, 'Аня, готовься к поздравлениям');

    final saved = DriftMembersRepository(db).applyProfilesFromServer(const [
      MemberProfile(
        userId: 'user-anya-67',
        displayName: 'Анна',
        avatarColor: CategoryColor.pink,
      ),
    ]);
    await tester.pumpAndSettle();
    await saved;
    await tester.pumpAndSettle();
    expect(
      tester.widget<HolidayBanner>(_banner).subtitle,
      'Анна, готовься к поздравлениям',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    now = DateTime(2026, 11, 14, 12);
    await startApp(
      tester,
      now: () => now,
      database: db,
      overrides: [
        sessionProvider.overrideWithBuild(
          (ref, _) => const SessionActive(anya),
        ),
        holidaySettingsProvider.overrideWithValue(
          HolidaySettings(birthday: anyaBirthday),
        ),
      ],
    );
    final day = tester.widget<HolidayBanner>(_banner);
    expect(day.type, HolidayBannerType.greeting);
    expect(day.title, 'С днём рождения, Анна!');
    expect(day.subtitle, 'Пусть миллион копится сам 🎂');
    await _tapClose(tester);

    final lines = logs.linesOf('holidays');
    expect(
      lines,
      contains(
        endsWith(
          'holiday banner shown holiday=birthday stage=before '
          'id=birthday:2026 type=countdown',
        ),
      ),
    );
    expect(lines, contains(contains('holiday banner hidden id=birthday:2026')));
    for (final secret in [
      'Аня',
      'Анна',
      'daysUntilDay',
      '11-14',
      '14.11',
      'ноябр',
    ]) {
      expect(lines.join('\n'), isNot(contains(secret)), reason: secret);
    }
  });

  test('в local_prefs не список - все плашки видны, warn с длиной', () async {
    final db = openTestDatabase();
    final prefs = DriftPrefsRepository(db);
    await prefs.setString(PrefKeys.hiddenHolidayBanners, '{"halloween":1}');

    expect(await loadHiddenHolidayBanners(prefs), isEmpty);
    expect(logs.linesOf('holidays', Level.WARNING), [
      endsWith(
        'hidden holiday banners ignored: key=hiddenHolidayBanners is not '
        'valid (expected a list of ids, got _Map<String, dynamic>) '
        'length=15 → every banner shown until the next close tap',
      ),
    ]);
  });
}
