import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/core/data_startup.dart';
import 'package:milionchik/data/api/token_store.dart';
import 'package:milionchik/data/db/app_database.dart';
import 'package:milionchik/data/dev_seed.dart';
import 'package:milionchik/data/providers.dart';
import 'package:milionchik/data/repositories/prefs_repository.dart';
import 'package:milionchik/data/session/session.dart';
import 'package:milionchik/features/profile/profile_screen.dart';
import 'package:milionchik/features/profile/theme_mode.dart';
import 'package:milionchik/features/profile/theme_screen.dart';
import 'package:milionchik/ui/components/bottom_nav.dart';
import 'package:milionchik/ui/components/radio.dart';
import 'package:milionchik/ui/components/snackbar.dart';

import '../../data/api/fake_api_adapter.dart';
import '../../support/app_scope.dart';
import 'profile_fixture.dart';
import 'profile_harness.dart';

Future<void> _openTheme(ProfileHarness h) async {
  await h.openProfile();
  await h.tap(h.row('Тема'));
  expect(find.byType(ThemeScreen), findsOneWidget);
}

bool _radioSelected(WidgetTester tester, String title) => tester
    .widget<AppRadio>(
      find.descendant(
        of: find.ancestor(
          of: find.text(title),
          matching: find.byType(MergeSemantics),
        ),
        matching: find.byType(AppRadio),
      ),
    )
    .selected;

Brightness _brightness(WidgetTester tester, Type screen) =>
    Theme.of(tester.element(find.byType(screen))).brightness;

final class _FailingPrefs implements PrefsRepository {
  _FailingPrefs(this._inner);

  final PrefsRepository _inner;

  @override
  Future<void> setString(String key, String value) async {
    if (key == PrefKeys.themeMode) throw StateError('disk full (test)');
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

Future<DevSeedResult> _noSeed(AppDatabase db) async =>
    const DevSeedResult(DevSeedStatus.off);

const Session _session = Session(
  user: profileUser,
  tokens: AuthTokens(
    accessToken: 'ACCESS-theme-uniform-victor',
    refreshToken: 'REFRESH-theme-whiskey-xray',
  ),
);

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testWidgets('«Тёмная» при светлой системе - приложение тёмное сразу, '
      'выбор в local_prefs, в профиле «Тёмная»', (tester) async {
    final h = await ProfileHarness.start(tester);
    await _openTheme(h);

    expect(h.appThemeMode, ThemeMode.system);
    expect(_radioSelected(tester, 'Как в системе'), isTrue);
    expect(find.text('Сейчас светлая'), findsOneWidget);
    expect(_brightness(tester, ThemeScreen), Brightness.light);

    await h.tap(find.text('Тёмная'));

    expect(h.appThemeMode, ThemeMode.dark);
    expect(_brightness(tester, ThemeScreen), Brightness.dark);
    expect(_radioSelected(tester, 'Тёмная'), isTrue);
    expect(_radioSelected(tester, 'Как в системе'), isFalse);
    expect(
      await tester.runAsync(
        () => DriftPrefsRepository(h.db).getString(PrefKeys.themeMode),
      ),
      'dark',
    );
    expect(
      h.linesOf('profile', Level.INFO),
      contains(
        matches(
          r'INFO  \[profile\] theme changed mode=dark previous=system '
          r'in \d+ms$',
        ),
      ),
    );

    await tester.tap(find.bySemanticsLabel('Назад').last);
    await h.settle();
    expect(h.valueOf('Тема'), 'Тёмная');
    expect(_brightness(tester, ProfileScreen), Brightness.dark);

    await h.tap(h.row('Тема'));
    await h.tap(find.text('Светлая'));
    expect(h.appThemeMode, ThemeMode.light);
    expect(_brightness(tester, ThemeScreen), Brightness.light);
  });

  testWidgets('выбранная тема переживает перезапуск: при старте читается '
      'из local_prefs до первого кадра', (tester) async {
    final logs = LogCapture();
    addTearDown(logs.dispose);
    final db = AppDatabase.memory();
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(360, 800);
    addTearDown(tester.view.reset);

    Future<DataReady> launch() async =>
        (await tester.runAsync(
              () => startData(
                open: () async => db,
                seed: _noSeed,
                readSession: () async => _session,
              ),
            ))!
            as DataReady;

    final first = await launch();
    expect(first.themeMode, ThemeMode.system);
    await tester.pumpWidget(appRoot(first));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AppBottomNav),
        matching: find.text('Профиль'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Тема'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Тема'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('Тёмная'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);

    final second = await launch();
    expect(second.themeMode, ThemeMode.dark);
    await tester.pumpWidget(appRoot(second));
    await tester.pumpAndSettle();

    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
    );
    expect(
      Theme.of(tester.element(find.byType(Scaffold).first)).brightness,
      Brightness.dark,
    );
    expect(
      logs.linesOf('profile', Level.INFO),
      containsAllInOrder([
        matches(r'INFO  \[profile\] theme mode=system: not chosen yet in '),
        matches(r'theme changed mode=dark previous=system in \d+ms$'),
        matches(
          r'INFO  \[profile\] theme mode=dark from key=themeMode in \d+ms$',
        ),
      ]),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
    await tester.runAsync(db.close);
  });

  test(
    'в local_prefs непонятное значение - тема как в системе и warn',
    () async {
      final logs = LogCapture();
      addTearDown(logs.dispose);
      final db = AppDatabase.memory();
      addTearDown(db.close);
      final prefs = DriftPrefsRepository(db);
      await prefs.setString(PrefKeys.themeMode, 'sepia');

      expect(await loadThemeMode(prefs), ThemeMode.system);
      expect(logs.linesOf('profile', Level.WARNING), [
        endsWith(
          'theme mode ignored: key=themeMode has unknown value length=5, '
          'starting with mode=system',
        ),
      ]);
    },
  );

  testWidgets('выбор не записался - тема прежняя, снекбар, warn с ошибкой', (
    tester,
  ) async {
    final db = openTestDatabase();
    final h = await ProfileHarness.start(
      tester,
      db: db,
      overrides: [
        prefsRepositoryProvider.overrideWithValue(
          _FailingPrefs(DriftPrefsRepository(db)),
        ),
      ],
    );
    await _openTheme(h);

    await h.tap(find.text('Тёмная'));

    expect(h.appThemeMode, ThemeMode.system);
    expect(_radioSelected(tester, 'Как в системе'), isTrue);
    expect(
      find.descendant(
        of: find.byType(AppSnackbar),
        matching: find.text('Не удалось сохранить тему. Попробуй ещё раз'),
      ),
      findsOneWidget,
    );
    expect(
      h.linesOf('profile', Level.WARNING),
      contains(
        allOf(
          contains('theme mode=dark not saved after '),
          contains('keeping mode=system: StateError'),
          contains('disk full (test)'),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
  });
}
