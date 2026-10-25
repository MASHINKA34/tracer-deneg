import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/data/providers.dart';
import 'package:milionchik/data/repositories/prefs_repository.dart';
import 'package:milionchik/data/sync/sync_triggers.dart';
import 'package:milionchik/features/holidays/birthday_sheet.dart';
import 'package:milionchik/features/holidays/holiday_settings_screen.dart';
import 'package:milionchik/features/holidays/mood_controller.dart';
import 'package:milionchik/features/profile/profile_screen.dart';
import 'package:milionchik/ui/components/bottom_nav.dart';
import 'package:milionchik/ui/components/month_card.dart';
import 'package:milionchik/ui/components/snackbar.dart';
import 'package:milionchik/ui/components/toggle.dart';
import 'package:shared/shared.dart';

import '../../data/api/fake_api_adapter.dart';
import '../../support/app_scope.dart';
import '../auth/session_expired_fixture.dart' show testUnmounting;
import '../profile/profile_fixture.dart';
import '../profile/profile_harness.dart';

final class _Server {
  bool online = true;
  bool enabled = true;
  Set<String> disabled = {};
  int? birthdayMonth;
  int? birthdayDay;

  final List<FakeCall> calls = [];

  List<Map<String, Object?>> get patches => [
    for (final c in calls)
      if (c.method == 'PATCH') c.json,
  ];

  Map<String, Object?> me() => {
    'id': profileUser.userId,
    'login': profileUser.login,
    'displayName': profileUser.displayName,
    'birthdayMonth': birthdayMonth,
    'birthdayDay': birthdayDay,
    'holidaysEnabled': enabled,
    'holidaysDisabled': disabled.toList()..sort(),
    'createdAt': '2026-09-01T09:00:00.000Z',
  };

  FakeReply handle(FakeCall call) {
    calls.add(call);
    if (!online) throw const SocketException('Network is unreachable');
    if (call.path.endsWith('/sync/pull')) {
      return FakeReply.json(
        200,
        SyncPullResponse(cursor: 0, hasMore: false).toJson(),
      );
    }
    if (call.path.endsWith('/me') && call.method == 'GET') {
      return FakeReply.json(200, me());
    }
    if (call.path.endsWith('/me') && call.method == 'PATCH') {
      final body = call.json;
      if (body.containsKey('holidaysEnabled')) {
        enabled = body['holidaysEnabled']! as bool;
      }
      if (body.containsKey('holidaysDisabled')) {
        disabled = (body['holidaysDisabled']! as List<Object?>)
            .cast<String>()
            .toSet();
      }
      if (body.containsKey('birthdayMonth')) {
        birthdayMonth = body['birthdayMonth'] as int?;
        birthdayDay = body['birthdayDay'] as int?;
      }
      return FakeReply.json(200, me());
    }
    throw StateError('unexpected ${call.method} ${call.path}');
  }
}

final class _FailingPrefs implements PrefsRepository {
  _FailingPrefs(this._inner);

  final PrefsRepository _inner;

  @override
  Future<void> setString(String key, String value) async {
    if (key == PrefKeys.holidaySettings) throw StateError('disk full (test)');
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

Finder _toggleOf(String title) => find.descendant(
  of: find.ancestor(of: find.text(title), matching: find.byType(InkWell)).first,
  matching: find.byType(AppToggle),
);

bool _isOn(WidgetTester tester, String title) =>
    tester.widget<AppToggle>(_toggleOf(title)).value;

Mood _mood(ProfileHarness h) => h.container.read(moodControllerProvider).mood;

Future<ProfileHarness> _openSettings(
  WidgetTester tester,
  _Server server, {
  DateTime? now,
  bool failingPrefs = false,
}) async {
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  final db = openTestDatabase();
  final h = await ProfileHarness.start(
    tester,
    server: server.handle,
    db: db,
    now: now,
    overrides: [
      if (failingPrefs)
        prefsRepositoryProvider.overrideWithValue(
          _FailingPrefs(DriftPrefsRepository(db)),
        ),
    ],
  );
  await h.openProfile();
  await h.tap(h.row('Праздники'));
  expect(find.byType(HolidaySettingsScreen), findsOneWidget);
  return h;
}

Future<void> _back(ProfileHarness h) async {
  await h.tester.tap(find.bySemanticsLabel('Назад').last);
  await h.settle();
}

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testUnmounting('31 октября: выключил Хеллоуин - настроение осени, PATCH '
      '/me, отметка 🎃 в календаре осталась', (tester) async {
    final server = _Server();
    final h = await _openSettings(
      tester,
      server,
      now: DateTime(2026, 10, 31, 12),
    );
    expect(_mood(h), Mood.halloween);
    expect(_isOn(tester, 'Хеллоуин'), isTrue);

    await h.tap(_toggleOf('Хеллоуин'));

    expect(_isOn(tester, 'Хеллоуин'), isFalse);
    expect(_mood(h), Mood.autumn);
    expect(server.patches, [
      {
        'holidaysDisabled': ['halloween'],
      },
    ]);
    expect(
      h.linesOf('holidays', Level.INFO),
      contains(
        contains(
          'holiday settings changed on the phone: halloween off → '
          'HolidaySettings(enabled: true, disabled: [halloween], birthday: '
          'none)',
        ),
      ),
    );

    await _back(h);
    await tester.tap(
      find.descendant(
        of: find.byType(AppBottomNav),
        matching: find.text('Месяц'),
      ),
    );
    await h.settle();
    expect(
      find.descendant(of: find.byType(MonthCard), matching: find.text('🎃')),
      findsOneWidget,
    );
  });

  testUnmounting('общий переключатель: выкл - в профиле «Выкл», PATCH '
      'holidaysEnabled=false; вкл - снова «Вкл»', (tester) async {
    final server = _Server();
    final h = await _openSettings(tester, server);

    await h.tap(find.text('Праздничное оформление'));

    expect(_isOn(tester, 'Праздничное оформление'), isFalse);
    expect(server.patches.last, {'holidaysEnabled': false});
    await _back(h);
    expect(find.byType(ProfileScreen), findsOneWidget);
    expect(h.valueOf('Праздники'), 'Выкл');

    await h.tap(h.row('Праздники'));
    await h.tap(_toggleOf('Праздничное оформление'));
    await _back(h);

    expect(h.valueOf('Праздники'), 'Вкл');
    expect(server.patches.last, {'holidaysEnabled': true});
    expect(server.patches, hasLength(2));
  });

  testUnmounting('мой ДР на завтра: шторка - октябрь, 20 → «20 октября», '
      'оформление ДР, PATCH с датой; в логах даты нет; «Очистить» - «Не '
      'указан», снова осень', (tester) async {
    final server = _Server();
    final h = await _openSettings(tester, server);
    expect(find.text('Не указан'), findsOneWidget);
    expect(find.text('Видна участникам общих бюджетов'), findsOneWidget);
    expect(_mood(h), Mood.autumn);

    await h.tap(find.text('Мой день рождения'));
    expect(find.byType(BirthdaySheet), findsOneWidget);
    expect(find.text('Очистить'), findsNothing);
    final sheet = find.byType(BirthdaySheet);
    await h.tap(find.descendant(of: sheet, matching: find.text('Октябрь')));
    await h.tap(find.descendant(of: sheet, matching: find.text('20')));
    await h.tap(find.text('Готово'));

    expect(find.byType(BirthdaySheet), findsNothing);
    expect(find.text('20 октября'), findsOneWidget);
    expect(_mood(h), Mood.birthday);
    expect(server.patches.single, {'birthdayMonth': 10, 'birthdayDay': 20});
    expect(
      h.linesOf('holidays', Level.INFO),
      contains(contains('holiday settings changed on the phone: birthday set')),
    );

    await h.tap(find.text('Мой день рождения'));
    await h.tap(find.text('Очистить'));

    expect(find.text('Не указан'), findsOneWidget);
    expect(_mood(h), Mood.autumn);
    expect(server.patches.last, {'birthdayMonth': null, 'birthdayDay': null});
    expect(
      h.linesOf('holidays', Level.INFO),
      contains(
        contains('holiday settings changed on the phone: birthday cleared'),
      ),
    );
    final text = h.logs.text;
    for (final leak in [
      '"birthdayMonth":10',
      '"birthdayDay":20',
      '20 октября',
      '20.10',
      '10/20',
      'MonthDay(',
    ]) {
      expect(text, isNot(contains(leak)), reason: '$leak leaked');
    }
  });

  testUnmounting('шторка: 31-е и смена месяца на февраль - день становится '
      '29-м; без выбора «Готово» недоступна', (tester) async {
    final server = _Server();
    final h = await _openSettings(tester, server);

    await h.tap(find.text('Мой день рождения'));
    final sheet = find.byType(BirthdaySheet);
    await h.tap(find.descendant(of: sheet, matching: find.text('31')));
    await h.tap(find.text('Готово'));
    expect(find.byType(BirthdaySheet), findsOneWidget);
    expect(server.patches, isEmpty);

    await h.tap(find.descendant(of: sheet, matching: find.text('Февраль')));
    expect(find.descendant(of: sheet, matching: find.text('31')), findsNothing);
    await h.tap(find.text('Готово'));

    expect(find.text('29 февраля'), findsOneWidget);
    expect(server.patches.single, {'birthdayMonth': 2, 'birthdayDay': 29});
    final sheetLines = [
      for (final line in h.linesOf('holidays'))
        if (line.contains('birthday sheet'))
          line.substring(line.indexOf('birthday sheet')),
    ];
    expect(sheetLines, hasLength(4));
    expect(
      sheetLines,
      everyElement(
        matches(
          RegExp(
            r'^birthday sheet (opened, date not set|month selected|day '
            r'selected|done after \d+ms)$',
          ),
        ),
      ),
    );
  });

  testUnmounting('без сети: переключатель меняется сразу, PATCH не прошёл - '
      'warn; появилась сеть - цикл синхронизации отправляет последнее '
      'состояние одним PATCH', (tester) async {
    final server = _Server();
    final h = await _openSettings(tester, server);
    final triggers = h.container.read(syncTriggersProvider)
      ..start(signedIn: true, foreground: true);
    await h.settle();
    triggers.networkChanged(const [ConnectivityResult.none]);
    server.online = false;

    await h.tap(_toggleOf('14 февраля'));
    await h.tap(_toggleOf('1 июня'));

    expect(_isOn(tester, '14 февраля'), isFalse);
    expect(_isOn(tester, '1 июня'), isFalse);
    expect(server.disabled, isEmpty);
    expect(
      h.linesOf('holidays', Level.WARNING),
      contains(
        contains(
          'ApiNetworkFailure: connection cause=SocketException: Network is '
          'unreachable',
        ),
      ),
    );
    expect(
      await tester.runAsync(
        () =>
            DriftPrefsRepository(h.db)
                .getString(PrefKeys.holidaySettingsUnsent),
      ),
      'holidaysDisabled',
    );

    server.online = true;
    final before = server.calls.length;
    triggers.networkChanged(const [ConnectivityResult.wifi]);
    await h.settle();

    final after = [
      for (final c in server.calls.sublist(before)) '${c.method} ${c.path}',
    ];
    expect(after, ['GET /api/v1/sync/pull', 'PATCH /api/v1/me']);
    expect(server.patches.last, {
      'holidaysDisabled': ['children', 'valentine'],
    });
    expect(server.disabled, {'children', 'valentine'});
    expect(
      await tester.runAsync(
        () =>
            DriftPrefsRepository(h.db)
                .getString(PrefKeys.holidaySettingsUnsent),
      ),
      isNull,
    );
    expect(
      h.linesOf('holidays', Level.INFO).last,
      contains('holiday settings sent (after pull network): PATCH /me'),
    );
  });

  testUnmounting('изменение не записалось в базу: переключатель прежний, '
      'снекбар, запроса нет', (tester) async {
    final server = _Server();
    final h = await _openSettings(tester, server, failingPrefs: true);

    await h.tap(_toggleOf('8 Марта'));

    expect(_isOn(tester, '8 Марта'), isTrue);
    expect(
      find.descendant(
        of: find.byType(AppSnackbar),
        matching: find.text(
          'Не удалось сохранить настройки праздников. Попробуй ещё раз',
        ),
      ),
      findsOneWidget,
    );
    expect(server.patches, isEmpty);
    expect(
      h.linesOf('holidays', Level.WARNING),
      contains(
        allOf(
          contains('holiday settings change "women off" not saved after '),
          contains('StateError: Bad state: disk full (test)'),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
  });
}
