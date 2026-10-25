import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/data/api/api_client.dart';
import 'package:milionchik/data/api/api_config.dart';
import 'package:milionchik/data/api/api_log_body.dart';
import 'package:milionchik/data/api/token_store.dart';

import 'fake_api_adapter.dart';

const _tokens = AuthTokens(
  accessToken: 'ACCESS-birthday-mask-oscar',
  refreshToken: 'REFRESH-birthday-mask-papa',
);

const int _month = 11;
const int _day = 23;

const int _memberMonth = 7;
const int _memberDay = 29;

Map<String, Object?> _me() => {
  'id': 'user-birthday-mask',
  'login': 'birthday_mask',
  'displayName': 'Аня',
  'birthdayMonth': _month,
  'birthdayDay': _day,
  'holidaysEnabled': true,
  'holidaysDisabled': ['knowledge'],
  'createdAt': '2026-10-01T09:00:00.000Z',
};

void _expectNoBirthday(String text, int month, int day) {
  for (final leak in [
    '"birthdayMonth":$month',
    '"birthdayDay":$day',
    '"birthdayMonth":"$month"',
    '"birthdayDay":"$day"',
  ]) {
    expect(text, isNot(contains(leak)), reason: '$leak leaked:\n$text');
  }
}

void main() {
  late LogCapture logs;
  final config = ApiConfig.resolve(define: '', debugBuild: true);

  setUp(() => logs = LogCapture(level: Level.ALL));
  tearDown(() => logs.dispose());

  ApiClient client(FakeApiAdapter adapter) => ApiClient(
    config: config,
    tokens: MemoryTokenStore(_tokens),
    adapter: adapter,
    newRequestId: () => 'ridbirthdaymask01',
  );

  test('GET /me на уровне ALL: тело ответа в логе, месяц и день рождения - '
      'маской', () async {
    final adapter = FakeApiAdapter((call) => FakeReply.json(200, _me()));

    await client(adapter).get('/me');

    final text = logs.text;
    expect(text, contains('← GET /api/v1/me 200'));
    expect(text, contains('"birthdayMonth":"***"'));
    expect(text, contains('"birthdayDay":"***"'));
    expect(text, contains('"holidaysDisabled":["knowledge"]'));
    _expectNoBirthday(text, _month, _day);
  });

  test('PATCH /me на уровне ALL: тело запроса и ответа в логе, месяц и день '
      'рождения - маской', () async {
    final adapter = FakeApiAdapter((call) => FakeReply.json(200, _me()));

    await client(adapter).patch(
      '/me',
      body: {
        'holidaysEnabled': true,
        'holidaysDisabled': ['knowledge'],
        'birthdayMonth': _month,
        'birthdayDay': _day,
      },
    );

    expect(adapter.calls.single.json['birthdayMonth'], _month);
    final text = logs.text;
    expect(text, contains('→ PATCH /api/v1/me'));
    expect(text, contains('← PATCH /api/v1/me 200'));
    expect(
      RegExp('"birthdayMonth":"\\*\\*\\*"').allMatches(text),
      hasLength(2),
    );
    expect(RegExp('"birthdayDay":"\\*\\*\\*"').allMatches(text), hasLength(2));
    _expectNoBirthday(text, _month, _day);
  });

  test('PATCH /me с очисткой даты: в запросе null как есть, дата из ответа '
      '- маской', () async {
    final adapter = FakeApiAdapter((call) => FakeReply.json(200, _me()));

    await client(
      adapter,
    ).patch('/me', body: {'birthdayMonth': null, 'birthdayDay': null});

    final text = logs.text;
    expect(text, contains('{"birthdayMonth":null,"birthdayDay":null}'));
    expect(text, contains('"birthdayMonth":"***"'));
    _expectNoBirthday(text, _month, _day);
  });

  test('pull: даты рождения участников в profiles - маской', () {
    final body = responseBodyForLog({
      'profiles': [
        {
          'userId': 'member-1',
          'displayName': 'Дима',
          'birthdayMonth': _memberMonth,
          'birthdayDay': _memberDay,
        },
      ],
      'cursor': 4100,
      'hasMore': false,
    })!;

    expect(body, contains('"birthdayMonth":"***"'));
    expect(body, contains('"cursor":4100'));
    _expectNoBirthday(body, _memberMonth, _memberDay);
  });
}
