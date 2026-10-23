import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/data/api/api_client.dart';
import 'package:milionchik/data/api/api_config.dart';
import 'package:milionchik/data/api/api_exception.dart';
import 'package:milionchik/data/api/api_log_body.dart';
import 'package:shared/logging.dart';

import 'fake_api_adapter.dart';

const _login = 'annalogin_secret';
const _password = 'Pass-Word-Secret-Seventy-Seven';
const _access = 'access-token-secret-aaaaaaaaaaaaaaaaaa';
const _refresh = 'refresh-token-secret-bbbbbbbbbbbbbbbbb';
const _recovery = 'RECOVERY-CODE-SECRETXYZ';
const _invite = 'MLN-SECRETINVITE';
const _comment = 'comment-text-secret-shawarma';
const _name = 'display-name-secret-anna';

void _expectNoSecrets(String text, List<String> secrets) {
  for (final secret in secrets) {
    expect(text, isNot(contains(secret)), reason: '$secret leaked:\n$text');
  }
}

void main() {
  late LogCapture logs;
  final config = ApiConfig.resolve(define: '', debugBuild: true);

  setUp(() => logs = LogCapture());
  tearDown(() => logs.dispose());

  test('debug: тело входа с маской логина и пароля, ответ с токенами не '
      'пишется', () async {
    final adapter = FakeApiAdapter(
      (call) => FakeReply.json(200, {
        'user': {'id': 'u1', 'login': _login, 'displayName': _name},
        'accessToken': _access,
        'refreshToken': _refresh,
      }),
    );
    final api = ApiClient(config: config, adapter: adapter);

    await api.post(
      '/auth/login',
      body: {'login': _login, 'password': _password, 'deviceName': 'Pixel 7'},
      auth: false,
    );

    final text = logs.text;
    expect(adapter.calls.single.json['password'], _password);
    expect(text, contains('"login":"an***"'));
    expect(text, contains('"password":"***(${_password.length})"'));
    expect(text, contains('"deviceName":"Pixel 7"'));
    expect(text, contains('<omitted: response with tokens>'));
    _expectNoSecrets(text, [_login, _password, _access, _refresh, _name]);
  });

  test('debug: refresh-токен в запросе, коды восстановления и приглашения, '
      'комментарий и имя - маской; код ошибки и rejected - как есть', () {
    final request = requestBodyForLog({'refreshToken': _refresh})!;
    final recovery = responseBodyForLog(
      '{"recoveryCode":"$_recovery","user":{"displayName":"$_name"}}',
    )!;
    final invite = requestBodyForLog({'code': _invite})!;
    final push = requestBodyForLog({
      'changes': [
        {
          'entity': 'expense',
          'data': {'amountKopecks': 64000, 'comment': _comment},
        },
      ],
    })!;
    final rejected = responseBodyForLog(
      '{"rejected":[{"id":"e1","code":"conflict"}],'
      '"error":{"code":"invite_not_found","message":"Код не найден"}}',
    )!;

    expect(request, '{"refreshToken":"***(${_refresh.length})"}');
    expect(recovery, contains('"recoveryCode":"****-****-****"'));
    expect(invite, '{"code":"MLN-****"}');
    expect(push, contains('"amountKopecks":64000'));
    expect(push, contains('"comment":"***(${_comment.length})"'));
    expect(rejected, contains('"code":"conflict"'));
    expect(rejected, contains('"code":"invite_not_found"'));
    _expectNoSecrets([request, recovery, invite, push].join('\n'), [
      _refresh,
      _recovery,
      _invite,
      _comment,
      _name,
    ]);
  });

  test('debug: тело длиннее 2 КБ обрезается с полным размером', () {
    final body = requestBodyForLog({'note': 'x' * 5000})!;

    expect(body, contains('…[truncated, total 5011 bytes]'));
    expect(body.length, lessThan(2100));
  });

  test(
    'сетевая ошибка с адресом в исключении - в логе путь без query',
    () async {
      final adapter = FakeApiAdapter(
        (call) => throw HttpException(
          'Connection closed before full header was received',
          uri: call.options.uri,
        ),
      );
      final api = ApiClient(config: config, adapter: adapter);

      Object? failure;
      try {
        await api.get(
          '/sync/pull',
          query: {'cursor': 'query-secret-marker'},
          auth: false,
        );
      } on ApiNetworkFailure catch (e) {
        failure = e;
      }

      expect(failure, isA<ApiNetworkFailure>());
      _expectNoSecrets(describeError(failure), ['query-secret-marker']);
      final text = logs.text;
      final warn = logs.linesOf('api', Level.WARNING).join('\n');
      expect(warn, contains('GET /api/v1/sync/pull failed in '));
      expect(warn, contains('HttpException: Connection closed'));
      expect(warn, contains('path=/api/v1/sync/pull'));
      _expectNoSecrets(text, ['query-secret-marker']);
    },
  );

  test('info: тела запросов и ответов не пишутся', () async {
    await logs.dispose();
    logs = LogCapture(level: Level.INFO);
    final adapter = FakeApiAdapter(
      (call) => FakeReply.json(200, {'status': 'ok', 'comment': _comment}),
    );
    final api = ApiClient(config: config, adapter: adapter);

    await api.post('/budgets', body: {'name': _name}, auth: false);

    expect(logs.text, isNot(contains('body=')));
    _expectNoSecrets(logs.text, [_name, _comment]);
  });
}
