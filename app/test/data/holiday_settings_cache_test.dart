import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/core/clock.dart';
import 'package:milionchik/core/data_startup.dart';
import 'package:milionchik/data/api/account_api.dart';
import 'package:milionchik/data/api/api_client.dart';
import 'package:milionchik/data/api/api_config.dart';
import 'package:milionchik/data/api/api_exception.dart';
import 'package:milionchik/data/api/api_providers.dart';
import 'package:milionchik/data/api/token_store.dart';
import 'package:milionchik/data/db/app_database.dart';
import 'package:milionchik/data/holiday_settings.dart';
import 'package:milionchik/data/providers.dart';
import 'package:milionchik/data/repositories/account_data_cleaner.dart';
import 'package:milionchik/data/repositories/prefs_repository.dart';
import 'package:milionchik/data/session/session.dart';
import 'package:milionchik/data/session/session_providers.dart';
import 'package:milionchik/data/session/session_state.dart';
import 'package:milionchik/data/sync/sync_engine.dart';
import 'package:shared/shared.dart';

import 'api/fake_api_adapter.dart';
import 'session/fake_secure_values.dart';

const _user = SessionUser(
  userId: 'user-holidays-51',
  login: 'holiday_user',
  displayName: 'Лиза',
);

const _tokens = AuthTokens(
  accessToken: 'ACCESS-holidays-kilo-lima',
  refreshToken: 'REFRESH-holidays-mike-november',
);

Map<String, Object?> _me({
  String id = 'user-holidays-51',
  bool enabled = true,
  List<String> disabled = const ['halloween', 'from-future-version'],
  int? birthdayMonth = 3,
  int? birthdayDay = 17,
}) => {
  'id': id,
  'login': 'holiday_user',
  'displayName': 'Лиза',
  'birthdayMonth': birthdayMonth,
  'birthdayDay': birthdayDay,
  'holidaysEnabled': enabled,
  'holidaysDisabled': disabled,
  'createdAt': '2026-10-01T09:00:00.000Z',
};

final class _Server {
  _Server(this.me);

  FakeReply Function() me;
  int _rid = 0;

  late final FakeApiAdapter adapter = FakeApiAdapter(handle);

  String nextRequestId() => 'ridholiday${(++_rid).toString().padLeft(6, '0')}';

  List<String> get paths => [for (final c in adapter.calls) c.path];

  FakeReply handle(FakeCall call) {
    if (call.path.endsWith('/sync/pull')) {
      return FakeReply.json(
        200,
        SyncPullResponse(cursor: 0, hasMore: false).toJson(),
      );
    }
    if (call.path.endsWith('/me') && call.method == 'GET') return me();
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

  ProviderContainer container(
    _Server server, {
    CachedHolidaySettings? cached,
    FakeSecureValues? values,
  }) {
    final c = ProviderContainer.test(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(
          Clock(now: () => DateTime(2026, 10, 31, 12)),
        ),
        if (values != null) secureValuesProvider.overrideWithValue(values),
        apiClientProvider.overrideWith(
          (ref) => ApiClient(
            config: config,
            tokens: MemoryTokenStore(_tokens),
            adapter: server.adapter,
            newRequestId: server.nextRequestId,
          ),
        ),
        sessionProvider.overrideWithBuild(
          (ref, _) => const SessionActive(_user),
        ),
        if (cached != null)
          startupHolidaySettingsProvider.overrideWithValue(cached),
      ],
    );
    c.listen(holidaySettingsProvider, (_, _) {});
    return c;
  }

  Future<String?> stored() =>
      DriftPrefsRepository(db).getString(PrefKeys.holidaySettings);

  List<String> holidays([Level from = Level.ALL]) =>
      logs.linesOf('holidays', from);

  test('цикл синхронизации: после pull - GET /me, настройки праздников в '
      'local_prefs и в провайдере; неизвестный ключ пропущен; в info нет '
      'даты рождения', () async {
    final server = _Server(() => FakeReply.json(200, _me()));
    final c = container(server);
    expect(c.read(holidaySettingsProvider), const HolidaySettings());

    final result = await c.read(syncEngineProvider).sync(SyncReason.manual);

    expect(result, isA<SyncCycleDone>());
    expect(server.paths, ['/api/v1/sync/pull', '/api/v1/me']);
    expect(
      server.adapter.calls.last.header('Authorization'),
      'Bearer ${_tokens.accessToken}',
    );
    final expected = HolidaySettings(
      disabled: const {HolidayKey.halloween},
      birthday: MonthDay(3, 17),
    );
    expect(c.read(holidaySettingsProvider), expected);
    final cache = decodeHolidaySettings((await stored())!);
    expect(cache.userId, _user.userId);
    expect(cache.settings, expected);
    expect(holidays(Level.INFO), [
      matches(
        RegExp(
          r'INFO  \[holidays\] holiday settings received from GET /me '
          r'rid=ridholiday000002 in \d+ms \(after pull manual\): '
          r'HolidaySettings\(enabled: true, disabled: \[halloween\], '
          r'birthday: set\) \(was not cached, defaults\) cached in \d+ms$',
        ),
      ),
    ]);
    for (final line in holidays(Level.INFO)) {
      expect(line, isNot(contains('3/17')));
      expect(line, isNot(contains('17.03')));
    }
  });

  test('повторный pull с теми же настройками: GET /me есть, кэш не '
      'переписывается, info нет', () async {
    final server = _Server(() => FakeReply.json(200, _me()));
    final c = container(server);
    await c.read(syncEngineProvider).sync(SyncReason.manual);
    await DriftPrefsRepository(db).setString(PrefKeys.holidaySettings, 'mark');

    await c.read(syncEngineProvider).sync(SyncReason.periodic);

    expect(server.paths.where((p) => p.endsWith('/me')), hasLength(2));
    expect(await stored(), 'mark');
    expect(holidays(Level.INFO), hasLength(1));
    expect(
      holidays(Level.FINE),
      contains(
        contains(
          'holiday settings unchanged from GET /me rid=ridholiday000004',
        ),
      ),
    );
  });

  test('GET /me ответил 503: warn с причиной и rid, цикл синхронизации '
      'всё равно завершён, остаются прежние настройки', () async {
    final server = _Server(
      () => FakeReply.error(503, 'internal', 'Сервер недоступен'),
    );
    final c = container(
      server,
      cached: const CachedHolidaySettings(
        userId: 'user-holidays-51',
        settings: HolidaySettings(enabled: false),
      ),
    );

    final result = await c.read(syncEngineProvider).sync(SyncReason.manual);

    expect(result, isA<SyncCycleDone>());
    expect(c.read(holidaySettingsProvider).enabled, isFalse);
    expect(await stored(), isNull);
    expect(holidays(Level.WARNING), [
      matches(
        RegExp(
          r'WARN  \[holidays\] holiday settings refresh \(after pull manual\) '
          r'failed after \d+ms userId=user-holidays-51: ApiServerFailure: .*'
          r'rid=ridholiday000002 → keeping cached HolidaySettings\(enabled: '
          r'false, disabled: \[\], birthday: none\), next try after the next '
          r'pull$',
        ),
      ),
    ]);
  });

  test('ответ /me про другого пользователя не применяется (warn)', () async {
    final server = _Server(
      () => FakeReply.json(200, _me(id: 'user-someone-else', enabled: false)),
    );
    final c = container(server);

    await c.read(syncEngineProvider).sync(SyncReason.manual);

    expect(c.read(holidaySettingsProvider), const HolidaySettings());
    expect(await stored(), isNull);
    expect(holidays(Level.WARNING), [
      contains(
        'ignored: answer is for userId=user-someone-else, session '
        'userId=user-holidays-51',
      ),
    ]);
  });

  test('сессия сменила пользователя: настройки прежнего забыты, по '
      'умолчанию до GET /me', () async {
    final server = _Server(() => FakeReply.json(200, _me(enabled: false)));
    final c = container(
      server,
      values: FakeSecureValues(),
      cached: const CachedHolidaySettings(
        userId: 'user-holidays-51',
        settings: HolidaySettings(enabled: false),
      ),
    );
    expect(c.read(holidaySettingsProvider).enabled, isFalse);

    await c.read(sessionProvider.notifier).clear();

    expect(c.read(holidaySettingsProvider), const HolidaySettings());
    expect(c.read(accountHolidaySettingsProvider), isNull);
    expect(holidays(Level.INFO), [
      endsWith(
        'holiday settings of userId=user-holidays-51 forgotten: session user '
        'user-holidays-51 → - → default settings until GET /me',
      ),
    ]);
  });

  test('старт: кэш читается в startData и действует до первого GET /me; '
      'info со сводкой без даты рождения', () async {
    await DriftPrefsRepository(db).setString(
      PrefKeys.holidaySettings,
      encodeHolidaySettings(
        CachedHolidaySettings(
          userId: _user.userId,
          settings: HolidaySettings(enabled: false, birthday: MonthDay(12, 5)),
        ),
      ),
    );

    final data = await startData(
      open: () async => db,
      readSession: () async => const Session(user: _user, tokens: _tokens),
    );

    final ready = data as DataReady;
    expect(ready.holidaySettings!.settings.enabled, isFalse);
    expect(ready.holidaySettings!.settings.birthday, MonthDay(12, 5));
    expect(holidays(Level.INFO), [
      matches(
        RegExp(
          r'INFO  \[holidays\] holiday settings from cache '
          r'userId=user-holidays-51 HolidaySettings\(enabled: false, '
          r'disabled: \[\], birthday: set\) in \d+ms$',
        ),
      ),
    ]);
  });

  test('битый кэш (ДР 31 февраля) и кэш другого аккаунта не применяются: '
      'warn без значений даты рождения', () async {
    final prefs = DriftPrefsRepository(db);
    await prefs.setString(
      PrefKeys.holidaySettings,
      jsonEncode({
        'userId': _user.userId,
        'enabled': true,
        'disabled': <String>[],
        'birthdayMonth': 2,
        'birthdayDay': 31,
      }),
    );

    expect(await loadHolidaySettings(prefs, userId: _user.userId), isNull);

    await prefs.setString(
      PrefKeys.holidaySettings,
      encodeHolidaySettings(
        const CachedHolidaySettings(
          userId: 'user-previous-account',
          settings: HolidaySettings(enabled: false),
        ),
      ),
    );
    expect(await loadHolidaySettings(prefs, userId: _user.userId), isNull);

    final warnings = holidays(Level.WARNING);
    expect(warnings, [
      contains(
        'holiday settings cache ignored: key=holidaySettings is not valid '
        '(birthdayMonth/birthdayDay: not a valid month and day (values not '
        'logged))',
      ),
      contains(
        'holiday settings cache ignored: saved for '
        'userId=user-previous-account, session userId=user-holidays-51',
      ),
    ]);
    expect(logs.text, isNot(contains('2/31')));
  });

  test('выход стирает кэш праздников: это настройка аккаунта, не '
      'телефона', () async {
    await DriftPrefsRepository(db).setString(
      PrefKeys.holidaySettings,
      encodeHolidaySettings(
        const CachedHolidaySettings(
          userId: 'user-holidays-51',
          settings: HolidaySettings(enabled: false),
        ),
      ),
    );

    final removal = await DriftAccountDataCleaner(db).clearAccountData('test');

    expect(PrefKeys.phoneSettings, isNot(contains(PrefKeys.holidaySettings)));
    expect(removal.prefs, contains(PrefKeys.holidaySettings));
    expect(await stored(), isNull);
  });

  group('AccountApi.me', () {
    AccountApi api(FakeApiAdapter adapter) => AccountApi(
      ApiClient(
        config: config,
        tokens: MemoryTokenStore(_tokens),
        adapter: adapter,
        newRequestId: () => 'ridaccountme0001',
      ),
    );

    test('GET /api/v1/me с токеном: пользователь с настройками '
        'праздников', () async {
      final adapter = FakeApiAdapter((call) => FakeReply.json(200, _me()));

      final reply = await api(adapter).me();

      final call = adapter.calls.single;
      expect(call.method, 'GET');
      expect(call.path, '/api/v1/me');
      expect(call.header('Authorization'), 'Bearer ${_tokens.accessToken}');
      expect(reply.user.id, _user.userId);
      expect(reply.user.holidaysDisabled, {'halloween', 'from-future-version'});
      expect(reply.requestId, 'ridaccountme0001');
      expect(reply.toString(), isNot(contains('Лиза')));
    });

    test('ответ без пользователя или с кривой датой рождения - '
        'ApiBadResponse, в warn нет значений даты', () async {
      final adapter = FakeApiAdapter(
        (call) => FakeReply.json(200, _me(birthdayMonth: 2, birthdayDay: 31)),
      );

      await expectLater(
        api(adapter).me(),
        throwsA(
          isA<ApiBadResponse>().having(
            (e) => e.details,
            'details',
            '200 me: birthdayMonth/birthdayDay: not a valid month and day '
                '(values not logged)',
          ),
        ),
      );
      expect(logs.linesOf('account', Level.WARNING), [
        contains(
          'GET /me 200 answered without a user → bad response: '
          'birthdayMonth/birthdayDay: not a valid month and day (values not '
          'logged) rid=ridaccountme0001',
        ),
      ]);
      expect(logs.text, isNot(contains('2/31')));

      final empty = FakeApiAdapter((call) => FakeReply.json(200, <Object>[]));
      await expectLater(api(empty).me(), throwsA(isA<ApiBadResponse>()));
    });
  });
}
