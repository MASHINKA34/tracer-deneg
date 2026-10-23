import 'dart:convert';

import 'package:server/auth/tokens.dart';
import 'package:test/test.dart';

import 'support/auth_support.dart';
import 'support/shared_budget_support.dart';
import 'support/test_support.dart';

const _messageMarker = 'StateError: MESSAGE-MARKER-ALPHA';
const _stackMarker = '#0 STACK-MARKER-BRAVO (package:app/main.dart:1:1)';
const _logsMarker = 'INFO [month] LOGS-MARKER-CHARLIE';
const _deviceMarker = 'DEVICE-MARKER-DELTA';

Map<String, Object?> _report({
  String kind = 'crash',
  Object? appVersion = '1.0.0+1',
  Object? androidSdk = 36,
  Object? deviceModel = _deviceMarker,
  Object? message = _messageMarker,
  Object? stack = _stackMarker,
  Object? logs = _logsMarker,
}) => {
  'kind': kind,
  'appVersion': appVersion,
  'androidSdk': androidSdk,
  'deviceModel': deviceModel,
  'message': message,
  'stack': stack,
  'logs': logs,
};

class _Clock {
  DateTime current = DateTime.now().toUtc();

  DateTime now() => current;
}

void main() {
  late LogCapture logs;
  late AuthHarness api;
  late _Clock clock;

  setUp(() async {
    logs = LogCapture();
    clock = _Clock();
    api = await AuthHarness.start(
      accessTokens: AccessTokens(testJwtSecret, now: clock.now),
    );
  });

  Future<List<Object?>> storedRow(String id) async {
    final rows = await api.db.execute(
      r'SELECT user_id::text, app_version, android_sdk, device_model, kind, '
      r'message, stack, logs FROM client_errors WHERE id = $1::uuid',
      parameters: [id],
    );
    expect(rows, hasLength(1), reason: 'report $id stored');
    return rows.first.toList();
  }

  Future<int> storedCount() =>
      api.count('SELECT count(*)::int FROM client_errors');

  void expectNoReportTexts() {
    for (final marker in [
      'MESSAGE-MARKER-ALPHA',
      'STACK-MARKER-BRAVO',
      'LOGS-MARKER-CHARLIE',
      _deviceMarker,
    ]) {
      expect(logs.text, isNot(contains(marker)), reason: marker);
    }
  }

  test('без токена → 202 с id, отчёт записан без userId, warn в логе '
      'с видом, версией, SDK и размерами без текстов отчёта', () async {
    final body = _report();
    final response = await api.post('/client-errors', body: body);

    expect(response.status, 202, reason: response.text);
    final id = response.json['id']! as String;
    expect(id, matches(RegExp(r'^[0-9a-f-]{36}$')));
    expect(await storedRow(id), [
      null,
      '1.0.0+1',
      36,
      _deviceMarker,
      'crash',
      _messageMarker,
      _stackMarker,
      _logsMarker,
    ]);

    final size = utf8.encode(jsonEncode(body)).length;
    expect(
      logs.text,
      contains(
        RegExp(
          'WARN  \\[client-errors\\] client error received id=$id kind=crash '
          'appVersion=1\\.0\\.0\\+1 androidSdk=36 userId=none auth=none '
          'size=$size messageBytes=${_messageMarker.length} '
          'messageHash=[0-9a-f]{12} stackBytes=${_stackMarker.length} '
          'logsBytes=${_logsMarker.length} in \\d+ms',
        ),
      ),
    );
    expect(
      logs.text,
      contains(RegExp(r'POST /api/v1/client-errors 202 in \d+ms')),
    );
    expectNoReportTexts();
  });

  test('с токеном → отчёт привязан к пользователю', () async {
    final anna = await registerTestUser(api, 'anna');
    logs.clear();

    final response = await api.post(
      '/client-errors',
      body: _report(kind: 'user_report', stack: null, androidSdk: null),
      bearer: anna.accessToken,
    );

    expect(response.status, 202, reason: response.text);
    final row = await storedRow(response.json['id']! as String);
    expect(row[0], anna.id);
    expect(row[2], isNull);
    expect(row[4], 'user_report');
    expect(row[6], isNull);
    expect(
      logs.text,
      contains(
        'kind=user_report appVersion=1.0.0+1 androidSdk=none '
        'userId=${anna.id} auth=ok',
      ),
    );
    expect(logs.text, isNot(contains(anna.accessToken)));
    expectNoReportTexts();
  });

  test('истёкший, отозванный или испорченный токен → 202 без userId, '
      'причина в логе', () async {
    clock.current = clock.current.subtract(const Duration(minutes: 16));
    final anna = await registerTestUser(api, 'anna');
    clock.current = DateTime.now().toUtc();
    final boris = await registerTestUser(api, 'boris');
    expect(
      (await api.post('/auth/logout', bearer: boris.accessToken)).status,
      204,
    );
    logs.clear();

    final cases = {anna.accessToken: 'expired', 'not-a-jwt': 'malformed'};
    for (final MapEntry(key: token, value: reason) in cases.entries) {
      final response = await api.post(
        '/client-errors',
        body: _report(),
        bearer: token,
      );
      expect(response.status, 202, reason: '$reason: ${response.text}');
      expect((await storedRow(response.json['id']! as String))[0], isNull);
      expect(logs.text, contains('userId=none auth=$reason size='));
    }

    final revoked = await api.post(
      '/client-errors',
      body: _report(),
      bearer: boris.accessToken,
    );
    expect(revoked.status, 202, reason: revoked.text);
    expect((await storedRow(revoked.json['id']! as String))[0], isNull);
    expect(logs.text, contains('userId=none auth=session_revoked size='));

    final basic = await api.post(
      '/client-errors',
      body: _report(),
      headers: {'authorization': 'Basic abc'},
    );
    expect(basic.status, 202, reason: basic.text);
    expect(logs.text, contains('userId=none auth=malformed_header size='));
    expect(await storedCount(), 4);
    expect(logs.text, isNot(contains(anna.accessToken)));
    expect(logs.text, isNot(contains(boris.accessToken)));
  });

  test('неверный формат → 400 bad_request, ничего не записано, '
      'значения из тела не попадают в лог', () async {
    final bodies = <String, String>{
      'not json': '{"kind": "crash", MESSAGE-MARKER-ALPHA',
      'array': '[1, 2, 3]',
      'no appVersion': jsonEncode(_report()..remove('appVersion')),
      'no message': jsonEncode(_report()..remove('message')),
      'unknown kind': jsonEncode(_report(kind: 'KIND-MARKER-ECHO')),
      'sdk as string': jsonEncode(_report(androidSdk: '36')),
      'sdk out of range': jsonEncode(_report(androidSdk: 3000000000)),
      'negative sdk': jsonEncode(_report(androidSdk: -1)),
      'logs as number': jsonEncode(_report(logs: 42)),
    };
    for (final MapEntry(key: name, value: raw) in bodies.entries) {
      final response = await api.post('/client-errors', rawBody: raw);
      expect(response.status, 400, reason: '$name: ${response.text}');
      expect(response.errorCode, 'bad_request', reason: name);
      expect(
        (response.json['error']! as Map<String, Object?>)['message'],
        startsWith('Неверный отчёт'),
        reason: name,
      );
      expect(response.text, isNot(contains('MARKER')), reason: name);
    }
    expect(await storedCount(), 0);
    expect(
      'client error rejected reason=bad_request'.allMatches(logs.text),
      hasLength(bodies.length),
    );
    expect(
      logs.text,
      contains(
        'client error rejected reason=bad_request '
        'problem="ClientErrorReport.kind: unknown value \\"…\\""',
      ),
    );
    expect(
      logs.text,
      contains('problem="ClientErrorReport.androidSdk: out of range'),
    );
    expect(logs.text, contains('problem="body is not UTF-8 JSON:'));
    expect(logs.text, isNot(contains('KIND-MARKER-ECHO')));
    expectNoReportTexts();
  });

  test('символ NUL в тексте не роняет запись: заменён на U+FFFD', () async {
    final nul = String.fromCharCode(0);
    final response = await api.post(
      '/client-errors',
      body: _report(message: 'Bad${nul}state', logs: 'a${nul}b${nul}c'),
    );

    expect(response.status, 202, reason: response.text);
    final row = await storedRow(response.json['id']! as String);
    final replacement = String.fromCharCode(0xFFFD);
    expect(row[5], 'Bad${replacement}state');
    expect(row[7], 'a${replacement}b${replacement}c');
    expect(logs.text, contains(RegExp(r'nulReplaced=3 in \d+ms')));
  });

  test('управляющие символы в appVersion не ломают строку лога', () async {
    final response = await api.post(
      '/client-errors',
      body: _report(appVersion: '1.0.0\nWARN  [server] forged line\r'),
    );

    expect(response.status, 202, reason: response.text);
    expect(logs.text, isNot(contains('\nWARN  [server] forged line')));
    expect(
      logs.text,
      contains('appVersion="1.0.0?WARN  [server] forged line?"'),
    );
    expect(
      (await storedRow(response.json['id']! as String))[1],
      '1.0.0\nWARN  [server] forged line\r',
    );
  });
}
