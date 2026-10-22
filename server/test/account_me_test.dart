import 'package:test/test.dart';

import 'support/auth_support.dart';
import 'support/shared_budget_support.dart';
import 'support/test_support.dart';

void main() {
  late LogCapture logs;
  late AuthHarness api;
  late TestUser anna;

  setUp(() async {
    logs = LogCapture();
    api = await AuthHarness.start();
    anna = await registerTestUser(api, 'anna', displayName: 'Аня');
    logs.clear();
  });

  Future<ApiResponse> getMe({String? bearer}) =>
      api.send('GET', '/me', bearer: bearer ?? anna.accessToken);

  Future<ApiResponse> patchMe(Object? body, {String? rawBody}) => api.send(
    'PATCH',
    '/me',
    body: body,
    rawBody: rawBody,
    bearer: anna.accessToken,
  );

  Future<List<Object?>> storedProfile() async {
    final rows = await api.db.execute(
      r'SELECT display_name, birthday_month, birthday_day, holidays_enabled, '
      r'holidays_disabled, seq FROM users WHERE id = $1::uuid',
      parameters: [anna.id],
    );
    return rows.single.toList();
  }

  Future<int> storedSeq() async => (await storedProfile()).last! as int;

  group('GET /me', () {
    test('профиль и настройки без хешей, no-store, лог с userId', () async {
      final response = await getMe();

      expect(response.status, 200);
      expect(response.headers['cache-control'], 'no-store');
      final json = response.json;
      expect(json['id'], anna.id);
      expect(json['login'], 'anna');
      expect(json['displayName'], 'Аня');
      expect(json['birthdayMonth'], isNull);
      expect(json['birthdayDay'], isNull);
      expect(json['holidaysEnabled'], true);
      expect(json['holidaysDisabled'], isEmpty);
      expect(json['createdAt'], isA<String>());
      expect(response.text, isNot(contains('hash')));
      expect(response.text, isNot(contains(r'$argon2id$')));
      expect(
        logs.text,
        contains(RegExp('INFO  \\[account\\] profile read userId=${anna.id} ')),
      );
    });

    test('без токена → 401 unauthorized', () async {
      final response = await api.send('GET', '/me');
      expect(response.status, 401);
      expect(response.errorCode, 'unauthorized');
    });
  });

  group('PATCH /me', () {
    test('день рождения 29 февраля сохраняется и виден в GET /me', () async {
      final response = await patchMe({'birthdayMonth': 2, 'birthdayDay': 29});

      expect(response.status, 200);
      expect(response.headers['cache-control'], 'no-store');
      expect(response.json['birthdayMonth'], 2);
      expect(response.json['birthdayDay'], 29);
      final me = await getMe();
      expect(me.json['birthdayMonth'], 2);
      expect(me.json['birthdayDay'], 29);
      expect(me.json['displayName'], 'Аня');
      final stored = await storedProfile();
      expect(stored.sublist(1, 3), [2, 29]);
      expect(
        logs.text,
        contains(
          RegExp(
            'INFO  \\[account\\] profile updated userId=${anna.id} '
            'changed=birthday seq=\\d+→\\d+ in \\d+ms',
          ),
        ),
      );
    });

    test('частичное обновление: остальные поля не трогаются', () async {
      expect(
        (await patchMe({'birthdayMonth': 12, 'birthdayDay': 2})).status,
        200,
      );

      final response = await patchMe({'holidaysEnabled': false});

      expect(response.status, 200);
      expect(response.json['holidaysEnabled'], false);
      expect(response.json['birthdayMonth'], 12);
      expect(response.json['birthdayDay'], 2);
      expect(response.json['displayName'], 'Аня');
      expect(response.json['holidaysDisabled'], isEmpty);
      expect(await storedProfile(), [
        'Аня',
        12,
        2,
        false,
        <String>[],
        isA<int>(),
      ]);
    });

    test(
      'имя обрезается по краям, ключи праздников без повторов и по порядку',
      () async {
        final response = await patchMe({
          'displayName': '  Анна Петровна  ',
          'holidaysDisabled': ['victory', 'birthday', 'newyear', 'victory'],
          'holidaysEnabled': true,
        });

        expect(response.status, 200);
        expect(response.json['displayName'], 'Анна Петровна');
        expect(response.json['holidaysDisabled'], [
          'birthday',
          'newyear',
          'victory',
        ]);
        final stored = await storedProfile();
        expect(stored[0], 'Анна Петровна');
        expect(stored[4], ['birthday', 'newyear', 'victory']);
        expect(
          logs.text,
          contains(
            'profile updated userId=${anna.id} '
            'changed=displayName,holidaysDisabled seq=',
          ),
        );
      },
    );

    test('день рождения можно очистить: месяц и день null', () async {
      await patchMe({'birthdayMonth': 3, 'birthdayDay': 8});

      final response = await patchMe({
        'birthdayMonth': null,
        'birthdayDay': null,
      });

      expect(response.status, 200);
      expect(response.json['birthdayMonth'], isNull);
      expect(response.json['birthdayDay'], isNull);
      expect((await storedProfile()).sublist(1, 3), [null, null]);
    });

    test('имя и день рождения дают новый seq профиля, праздники и пустая правка — нет', () async {
      final initial = await storedSeq();

      await patchMe({'displayName': 'Анна'});
      final afterName = await storedSeq();
      expect(afterName, greaterThan(initial));

      await patchMe({'birthdayMonth': 7, 'birthdayDay': 1});
      final afterBirthday = await storedSeq();
      expect(afterBirthday, greaterThan(afterName));

      await patchMe({
        'holidaysEnabled': false,
        'holidaysDisabled': ['halloween'],
      });
      expect(await storedSeq(), afterBirthday);

      logs.clear();
      final same = await patchMe({'displayName': 'Анна'});
      expect(same.status, 200);
      expect(await storedSeq(), afterBirthday);
      expect(
        logs.text,
        contains(
          'INFO  [account] profile update without changes userId=${anna.id} '
          'requested=displayName seq=$afterBirthday',
        ),
      );
    });

    final rejected = <String, (Object?, int, String)>{
      'неизвестный ключ праздника': (
        {
          'holidaysDisabled': ['newyear', 'nope'],
        },
        400,
        'holiday_key_unknown',
      ),
      '31 апреля': (
        {'birthdayMonth': 4, 'birthdayDay': 31},
        400,
        'birthday_invalid',
      ),
      '30 февраля': (
        {'birthdayMonth': 2, 'birthdayDay': 30},
        400,
        'birthday_invalid',
      ),
      '13-й месяц': (
        {'birthdayMonth': 13, 'birthdayDay': 1},
        400,
        'birthday_invalid',
      ),
      'день 0': (
        {'birthdayMonth': 5, 'birthdayDay': 0},
        400,
        'birthday_invalid',
      ),
      'только месяц': ({'birthdayMonth': 5}, 400, 'birthday_invalid'),
      'месяц без дня (null)': (
        {'birthdayMonth': 5, 'birthdayDay': null},
        400,
        'birthday_invalid',
      ),
      'пустое имя': ({'displayName': '   '}, 400, 'name_empty'),
      'имя длиннее 40': ({'displayName': 'а' * 41}, 400, 'name_too_long'),
      'имя не строка': ({'displayName': 5}, 400, 'bad_request'),
      'месяц строкой': (
        {'birthdayMonth': '2', 'birthdayDay': 29},
        400,
        'bad_request',
      ),
      'день дробным': (
        {'birthdayMonth': 2, 'birthdayDay': 2.5},
        400,
        'bad_request',
      ),
      'holidaysEnabled не bool': (
        {'holidaysEnabled': 'yes'},
        400,
        'bad_request',
      ),
      'holidaysDisabled не список': (
        {'holidaysDisabled': 'newyear'},
        400,
        'bad_request',
      ),
      'holidaysDisabled с числом': (
        {
          'holidaysDisabled': ['newyear', 1],
        },
        400,
        'bad_request',
      ),
      'логин через /me': ({'login': 'boris'}, 400, 'bad_request'),
      'тело — массив': (['displayName'], 400, 'bad_request'),
    };

    for (final MapEntry(key: name, value: (body, status, code))
        in rejected.entries) {
      test('$name → $status $code, профиль не изменился', () async {
        final before = await storedProfile();

        final response = await patchMe(body);

        expect(response.status, status);
        expect(response.errorCode, code);
        expect(
          (response.json['error']! as Map<String, Object?>)['message'],
          isNotEmpty,
        );
        expect(await storedProfile(), before);
        expect(
          logs.text,
          contains(
            RegExp(
              'WARN  \\[account\\] profile update rejected reason=$code '
              'userId=${anna.id} ',
            ),
          ),
        );
        expect(logs.text, isNot(contains('profile updated')));
      });
    }

    test('тело не JSON → 400 bad_request', () async {
      final before = await storedProfile();
      final response = await patchMe(null, rawBody: '{"displayName": ');
      expect(response.status, 400);
      expect(response.errorCode, 'bad_request');
      expect(await storedProfile(), before);
    });

    test('без токена → 401 unauthorized, профиль не изменился', () async {
      final before = await storedProfile();
      final response = await api.send(
        'PATCH',
        '/me',
        body: {'displayName': 'Чужой'},
      );
      expect(response.status, 401);
      expect(response.errorCode, 'unauthorized');
      expect(await storedProfile(), before);
    });
  });
}
