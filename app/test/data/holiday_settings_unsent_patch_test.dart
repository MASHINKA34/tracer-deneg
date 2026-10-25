import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/core/clock.dart';
import 'package:milionchik/core/data_startup.dart';
import 'package:milionchik/data/api/api_client.dart';
import 'package:milionchik/data/api/api_config.dart';
import 'package:milionchik/data/api/api_providers.dart';
import 'package:milionchik/data/api/token_store.dart';
import 'package:milionchik/data/db/app_database.dart';
import 'package:milionchik/data/holiday_settings.dart';
import 'package:milionchik/data/providers.dart';
import 'package:milionchik/data/repositories/prefs_repository.dart';
import 'package:milionchik/data/session/session.dart';
import 'package:milionchik/data/session/session_providers.dart';
import 'package:milionchik/data/session/session_state.dart';
import 'package:milionchik/data/sync/sync_engine.dart';
import 'package:shared/shared.dart';

import 'api/fake_api_adapter.dart';

const _user = SessionUser(
  userId: 'user-unsent-71',
  login: 'unsent_user',
  displayName: 'Лиза',
);

const _tokens = AuthTokens(
  accessToken: 'ACCESS-unsent-quebec',
  refreshToken: 'REFRESH-unsent-romeo',
);

final class _Server {
  bool online = true;
  bool enabled = true;
  Set<String> disabled = {'from-future-version'};
  int? birthdayMonth = 3;
  int? birthdayDay = 17;
  FakeReply? patchReply;
  Completer<void>? patchGate;
  int _rid = 0;

  late final FakeApiAdapter adapter = FakeApiAdapter(handle);

  String nextRequestId() => 'ridunsent${(++_rid).toString().padLeft(6, '0')}';

  List<String> get calls => [
    for (final c in adapter.calls) '${c.method} ${c.path}',
  ];

  List<Map<String, Object?>> get patches => [
    for (final c in adapter.calls)
      if (c.method == 'PATCH') c.json,
  ];

  Map<String, Object?> me() => {
    'id': _user.userId,
    'login': _user.login,
    'displayName': _user.displayName,
    'birthdayMonth': birthdayMonth,
    'birthdayDay': birthdayDay,
    'holidaysEnabled': enabled,
    'holidaysDisabled': disabled.toList()..sort(),
    'createdAt': '2026-10-01T09:00:00.000Z',
  };

  Future<FakeReply> handle(FakeCall call) async {
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
      final gate = patchGate;
      if (gate != null) {
        patchGate = null;
        await gate.future;
      }
      final reply = patchReply;
      if (reply != null) return reply;
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

void main() {
  late LogCapture logs;
  late AppDatabase db;

  setUp(() {
    logs = LogCapture();
    db = AppDatabase.memory();
  });

  tearDown(() async {
    await logs.dispose();
    await db.close();
  });

  final config = ApiConfig.resolve(define: '', debugBuild: true);

  final fromServer = CachedHolidaySettings(
    userId: _user.userId,
    settings: HolidaySettings(birthday: MonthDay(3, 17)),
    otherDisabled: const {'from-future-version'},
  );

  ProviderContainer container(
    _Server server, {
    CachedHolidaySettings? cached,
    SessionState session = const SessionActive(_user),
  }) {
    final c = ProviderContainer.test(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(
          Clock(now: () => DateTime(2026, 10, 25, 12)),
        ),
        apiClientProvider.overrideWith(
          (ref) => ApiClient(
            config: config,
            tokens: MemoryTokenStore(_tokens),
            adapter: server.adapter,
            newRequestId: server.nextRequestId,
          ),
        ),
        sessionProvider.overrideWithBuild((ref, _) => session),
        if (cached != null)
          startupHolidaySettingsProvider.overrideWithValue(cached),
      ],
    );
    c.listen(holidaySettingsProvider, (_, _) {});
    return c;
  }

  AccountHolidaySettings notifier(ProviderContainer c) =>
      c.read(accountHolidaySettingsProvider.notifier);

  Future<String?> unsent() =>
      DriftPrefsRepository(db).getString(PrefKeys.holidaySettingsUnsent);

  Future<CachedHolidaySettings?> cache() async {
    final text = await DriftPrefsRepository(db)
        .getString(PrefKeys.holidaySettings);
    return text == null ? null : decodeHolidaySettings(text);
  }

  List<String> holidays([Level from = Level.ALL]) =>
      logs.linesOf('holidays', from);

  void expectNoBirthdayValues(int month, int day) {
    final text = logs.text;
    for (final leak in [
      '"birthdayMonth":$month',
      '"birthdayDay":$day',
      '$month/$day',
      '$day.${'$month'.padLeft(2, '0')}',
      'MonthDay(',
    ]) {
      expect(text, isNot(contains(leak)), reason: '$leak leaked:\n$text');
    }
  }

  test('при сети: выключил Хеллоуин - сразу PATCH /me только со списком '
      'выключенных (ключ будущей версии сохранён), ответ применён, флаг '
      'снят; info - что выключено, без даты рождения', () async {
    final server = _Server();
    final c = container(server, cached: fromServer);

    expect(await notifier(c).setHoliday(HolidayKey.halloween, false), isTrue);
    expect(c.read(holidaySettingsProvider).disabled, {HolidayKey.halloween});
    await notifier(c).sending;

    expect(server.calls, ['PATCH /api/v1/me']);
    expect(server.patches.single, {
      'holidaysDisabled': ['from-future-version', 'halloween'],
    });
    expect(await unsent(), isNull);
    expect((await cache())!.settings.disabled, {HolidayKey.halloween});
    expect((await cache())!.otherDisabled, {'from-future-version'});
    expect(holidays(Level.INFO), [
      matches(
        RegExp(
          r'INFO  \[holidays\] holiday settings changed on the phone: '
          r'halloween off → HolidaySettings\(enabled: true, disabled: '
          r'\[halloween\], birthday: set\), saved in \d+ms, '
          r'unsent=holidaysDisabled → PATCH /me$',
        ),
      ),
      matches(
        RegExp(
          r'INFO  \[holidays\] holiday settings sent \(changed on the phone\): '
          r'PATCH /me rid=ridunsent000001 fields=holidaysDisabled in \d+ms → '
          r'HolidaySettings\(enabled: true, disabled: \[halloween\], '
          r'birthday: set\)$',
        ),
      ),
    ]);
    expectNoBirthdayValues(3, 17);
  });

  test('без сети: изменения остаются на телефоне с флагом, warn с rid; при '
      'появлении сети цикл синхронизации шлёт один PATCH с последним '
      'состоянием вместо GET', () async {
    final server = _Server()..online = false;
    final c = container(server, cached: fromServer);

    await notifier(c).setHoliday(HolidayKey.halloween, false);
    await notifier(c).sending;
    await notifier(c).setBirthday(MonthDay(12, 5));
    await notifier(c).sending;

    expect(c.read(holidaySettingsProvider).birthday, MonthDay(12, 5));
    expect(await unsent(), 'holidaysDisabled,birthday');
    expect((await cache())!.settings.birthday, MonthDay(12, 5));
    expect(server.patches, hasLength(2));
    expect(
      holidays(Level.WARNING),
      everyElement(
        matches(
          RegExp(
            r'WARN  \[holidays\] holiday settings send \(changed on the '
            r'phone\) failed after \d+ms userId=user-unsent-71: '
            r'ApiNetworkFailure: connection .*rid=ridunsent\d+ → settings '
            r'stay unsent, next try on start, network or after pull$',
          ),
        ),
      ),
    );
    expect(holidays(Level.WARNING), hasLength(2));

    server.online = true;
    final calls = server.adapter.calls.length;
    final result = await c.read(syncEngineProvider).sync(SyncReason.network);

    expect(result, isA<SyncCycleDone>());
    expect(server.calls.sublist(calls), [
      'GET /api/v1/sync/pull',
      'PATCH /api/v1/me',
    ]);
    expect(server.patches.sublist(2).single, {
      'holidaysDisabled': ['from-future-version', 'halloween'],
      'birthdayMonth': 12,
      'birthdayDay': 5,
    });
    expect(await unsent(), isNull);
    expect(c.read(holidaySettingsProvider).birthday, MonthDay(12, 5));
    expect(
      holidays(Level.INFO).last,
      contains(
        'holiday settings sent (after pull network): PATCH /me '
        'rid=ridunsent000004 fields=holidaysDisabled,birthday',
      ),
    );
    expectNoBirthdayValues(12, 5);
  });

  test('ответ GET /me не затирает неотправленное изменение', () async {
    final server = _Server()..online = false;
    final c = container(server, cached: fromServer);
    await notifier(c).setEnabled(false);
    await notifier(c).sending;

    final applied = await notifier(c)
        .apply(User.fromJson(server.me()), source: 'GET /me test');

    expect(applied, isFalse);
    expect(c.read(holidaySettingsProvider).enabled, isFalse);
    expect((await cache())!.settings.enabled, isFalse);
    expect(await unsent(), 'holidaysEnabled');
    expect(
      holidays(Level.INFO),
      contains(
        endsWith(
          'holiday settings from GET /me test not applied: changed on the '
          'phone and not sent yet fields=holidaysEnabled → PATCH /me goes '
          'first',
        ),
      ),
    );
  });

  test('сервер отклонил PATCH (400): изменение снято, флаг удалён, настройки '
      'с сервера через GET /me', () async {
    final server = _Server()
      ..patchReply = FakeReply.error(
        400,
        'birthday_invalid',
        'Такой даты нет: укажи и день, и месяц существующей даты',
      );
    final c = container(server, cached: fromServer);

    await notifier(c).setBirthday(MonthDay(2, 29));
    await notifier(c).sending;

    expect(server.calls, ['PATCH /api/v1/me', 'GET /api/v1/me']);
    expect(await unsent(), isNull);
    expect(c.read(holidaySettingsProvider).birthday, MonthDay(3, 17));
    expect(
      holidays(Level.WARNING),
      contains(
        matches(
          RegExp(
            r'holiday settings send \(changed on the phone\) rejected after '
            r'\d+ms userId=user-unsent-71: 400 code=birthday_invalid '
            r'rid=ridunsent000001 → change on the phone dropped, server '
            r'settings come with GET /me$',
          ),
        ),
      ),
    );
    expectNoBirthdayValues(2, 29);
  });

  test('изменение во время отправки: ответ на прежнее не применяется, '
      'следом второй PATCH с новым состоянием', () async {
    final server = _Server()..patchGate = Completer<void>();
    final gate = server.patchGate!;
    final c = container(server, cached: fromServer);

    await notifier(c).setHoliday(HolidayKey.halloween, false);
    await pumpEventQueue();
    expect(server.patches, hasLength(1));
    await notifier(c).setHoliday(HolidayKey.valentine, false);
    gate.complete();
    await notifier(c).sending;

    expect(server.patches, [
      {
        'holidaysDisabled': ['from-future-version', 'halloween'],
      },
      {
        'holidaysDisabled': ['from-future-version', 'halloween', 'valentine'],
      },
    ]);
    expect(c.read(holidaySettingsProvider).disabled, {
      HolidayKey.halloween,
      HolidayKey.valentine,
    });
    expect(await unsent(), isNull);
    expect(
      holidays(Level.FINE),
      contains(
        contains(
          'but they changed on the phone meanwhile → answer not applied, '
          'sending the newer settings',
        ),
      ),
    );
  });

  test('старт с неотправленными настройками: info при чтении кэша, первый '
      'цикл синхронизации отправляет их PATCH /me', () async {
    final prefs = DriftPrefsRepository(db);
    await prefs.setString(
      PrefKeys.holidaySettings,
      encodeHolidaySettings(
        CachedHolidaySettings(
          userId: _user.userId,
          settings: const HolidaySettings(enabled: false),
        ),
      ),
    );
    await prefs.setString(PrefKeys.holidaySettingsUnsent, 'holidaysEnabled');

    final data = await startData(
      open: () async => db,
      readSession: () async => const Session(user: _user, tokens: _tokens),
    );
    final ready = data as DataReady;
    expect(
      holidays(Level.INFO),
      contains(
        matches(
          RegExp(
            r'holiday settings: changed on the phone and not sent yet '
            r'fields=holidaysEnabled \(read in \d+ms\) → PATCH /me after '
            r'the startup sync$',
          ),
        ),
      ),
    );

    final server = _Server();
    final c = container(server, cached: ready.holidaySettings);
    await c.read(syncEngineProvider).sync(SyncReason.startup);

    expect(server.calls, ['GET /api/v1/sync/pull', 'PATCH /api/v1/me']);
    expect(server.patches.single, {'holidaysEnabled': false});
    expect(await unsent(), isNull);
    expect(c.read(holidaySettingsProvider).enabled, isFalse);
  });

  test('фоновый изолят без кэша в памяти: неотправленное берётся из базы и '
      'уходит PATCH, а не затирается GET', () async {
    final prefs = DriftPrefsRepository(db);
    await prefs.setString(
      PrefKeys.holidaySettings,
      encodeHolidaySettings(
        CachedHolidaySettings(
          userId: _user.userId,
          settings: const HolidaySettings(disabled: {HolidayKey.newyear}),
        ),
      ),
    );
    await prefs.setString(PrefKeys.holidaySettingsUnsent, 'holidaysDisabled');
    final server = _Server();
    final c = container(server);

    await c.read(syncEngineProvider).sync(SyncReason.background);

    expect(server.calls, ['GET /api/v1/sync/pull', 'PATCH /api/v1/me']);
    expect(server.patches.single, {
      'holidaysDisabled': ['newyear'],
    });
    expect(await unsent(), isNull);
    expect((await cache())!.settings.disabled, {HolidayKey.newyear});
  });

  test(
    'без сессии: изменение только на телефоне, без флага и запросов',
    () async {
      final server = _Server();
      final c = container(server, session: const SessionAbsent());

      await notifier(c).setHoliday(HolidayKey.women, false);
      await notifier(c).sending;

      expect(c.read(holidaySettingsProvider).disabled, {HolidayKey.women});
      expect(server.calls, isEmpty);
      expect(await unsent(), isNull);
      expect(
        holidays(Level.INFO).single,
        endsWith(', no session → stays on the phone'),
      );
    },
  );
}
