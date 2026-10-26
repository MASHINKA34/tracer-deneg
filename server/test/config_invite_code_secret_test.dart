import 'package:server/config/config.dart';
import 'package:server/server_app.dart';
import 'package:test/test.dart';

import 'support/test_support.dart';

const _url = 'postgres://milionchik:milionchik@127.0.0.1:5434/milionchik';
final _jwt = 'j' * 40;

Matcher _problem(String text) => isA<ConfigException>().having(
  (e) => e.problems,
  'problems',
  contains(text),
);

void main() {
  test('без INVITE_CODE_SECRET — ошибка конфига', () {
    expect(
      () => ServerConfig.load(
        environment: {'DATABASE_URL': _url, 'JWT_SECRET': _jwt},
      ),
      throwsA(
        _problem('INVITE_CODE_SECRET is required (random string, ≥ 32 chars)'),
      ),
    );
    expect(
      () => ServerConfig.load(
        environment: {
          'DATABASE_URL': _url,
          'JWT_SECRET': _jwt,
          'INVITE_CODE_SECRET': '   ',
        },
      ),
      throwsA(
        _problem('INVITE_CODE_SECRET is required (random string, ≥ 32 chars)'),
      ),
    );
  });

  test('короче 32 символов — ошибка, 32 — можно', () {
    expect(
      () => ServerConfig.load(
        environment: {
          'DATABASE_URL': _url,
          'JWT_SECRET': _jwt,
          'INVITE_CODE_SECRET': 's' * 31,
        },
      ),
      throwsA(
        _problem('INVITE_CODE_SECRET is too short (31 chars), need ≥ 32'),
      ),
    );
    final config = ServerConfig.load(
      environment: {'DATABASE_URL': _url, 'JWT_SECRET': _jwt},
      dotEnv: {'INVITE_CODE_SECRET': 's' * 32},
    );
    expect(config.inviteCodeSecret, 's' * 32);
  });

  test('переменная окружения важнее .env; в лог-контексте только длина', () {
    final secret = 'invite-${'k' * 40}';
    final config = ServerConfig.load(
      environment: {
        'DATABASE_URL': _url,
        'JWT_SECRET': _jwt,
        'INVITE_CODE_SECRET': secret,
      },
      dotEnv: {'INVITE_CODE_SECRET': 'from-dotenv-${'d' * 32}'},
    );
    expect(config.inviteCodeSecret, secret);
    final context = config.toLogContext();
    expect(context['inviteCodeSecret'], '***(${secret.length})');
    expect(context.toString(), isNot(contains(secret)));
  });

  test('runServerProcess без INVITE_CODE_SECRET → код 1, понятная строка в '
      'логе, к базе не подключается', () async {
    final logs = LogCapture();
    final code = await runServerProcess(
      environment: {
        'HOST': '127.0.0.1',
        'PORT': '0',
        'DATABASE_URL': testDatabaseUrl(),
        'JWT_SECRET': _jwt,
      },
      setLogLevel: (_) {},
    );

    expect(code, 1);
    expect(
      logs.text,
      contains(
        'ERROR [server] config invalid: INVITE_CODE_SECRET is required '
        '(random string, ≥ 32 chars)',
      ),
    );
    expect(logs.text, isNot(contains('connecting to Postgres')));
    expect(logs.text, isNot(contains(_jwt)));
  });
}
