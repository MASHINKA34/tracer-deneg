// Тесты против настоящего PostgreSQL из deploy/docker-compose.test.yml.
import 'dart:convert';
import 'dart:io';

import 'package:server/config/config.dart';
import 'package:server/db/database.dart';
import 'package:server/http/health.dart';
import 'package:server/server_app.dart';
import 'package:server/version.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'support/test_support.dart';

Request _health() =>
    Request('GET', Uri.parse('http://localhost/api/v1/health'));

void main() {
  late LogCapture logs;
  setUp(() => logs = LogCapture());

  group('Database.connect', () {
    test('подключается к тестовой базе и знает её версию', () async {
      final db = await Database.connect(testDatabaseConfig(), attempts: 1);
      addTearDown(db.close);
      expect(await db.serverVersion(), startsWith('18.'));
      expect(logs.text, contains('Postgres connected in'));
    });

    test('база недоступна — N попыток с логом каждой, затем ошибка', () async {
      final dead = await deadDatabaseConfig();
      await expectLater(
        Database.connect(
          dead,
          attempts: 3,
          delays: const [Duration(milliseconds: 10)],
        ),
        throwsA(isA<SocketException>()),
      );
      expect(
        logs.text,
        contains('INFO  [db] connecting to Postgres 127.0.0.1:${dead.port}'),
      );
      expect(
        logs.text,
        contains(
          'WARN  [db] Postgres connect failed 127.0.0.1:${dead.port} (attempt 1/3)',
        ),
      );
      expect(logs.text, contains('(attempt 2/3)'));
      expect(
        logs.text,
        contains(
          'ERROR [db] Postgres connect failed 127.0.0.1:${dead.port} (attempt 3/3), giving up',
        ),
      );
      expect(logs.text, contains('  stack:'));
    });
  });

  group('GET /api/v1/health', () {
    test('база работает → 200 ok', () async {
      final db = Database.open(testDatabaseConfig());
      addTearDown(db.close);
      final response = await healthHandler(db)(_health());
      expect(response.statusCode, 200);
      expect(jsonDecode(await response.readAsString()), {
        'status': 'ok',
        'version': serverVersion,
        'db': 'ok',
      });
    });

    test('база недоступна → 503 без подробностей, причина в логе', () async {
      final db = Database.open(await deadDatabaseConfig());
      addTearDown(db.close);
      final response = await healthHandler(db)(_health());
      expect(response.statusCode, 503);
      expect(jsonDecode(await response.readAsString()), {
        'status': 'degraded',
        'version': serverVersion,
        'db': 'error',
      });
      expect(logs.text, contains('WARN  [health] database check failed'));
      expect(logs.text, contains('SocketException'));
    });
  });

  group('сервер целиком', () {
    test('старт → health по HTTP → остановка с логом каждого шага', () async {
      final config = ServerConfig.load(
        environment: {
          'HOST': '127.0.0.1',
          'PORT': '0',
          'DATABASE_URL': testDatabaseUrl(),
          'JWT_SECRET': 'x' * 32,
          'INVITE_CODE_SECRET': 'invite-code-secret-0123456789-abcdef',
        },
      );
      final server = await startServer(config, dbConnectAttempts: 1);

      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final request = await client.get(
        '127.0.0.1',
        server.port,
        '/api/v1/health',
      );
      request.headers.set('X-Request-Id', 'e2e-1');
      final response = await request.close();
      final body = jsonDecode(await response.transform(utf8.decoder).join());
      expect(response.statusCode, 200);
      expect(response.headers.value('x-request-id'), 'e2e-1');
      expect(body, containsPair('db', 'ok'));

      final notFound = await (await client.get(
        '127.0.0.1',
        server.port,
        '/nope',
      )).close();
      expect(notFound.statusCode, 404);
      expect(jsonDecode(await notFound.transform(utf8.decoder).join()), {
        'error': {'code': 'not_found', 'message': 'Не найдено'},
      });

      await server.shutdown('test');
      expect(
        logs.text,
        contains(
          RegExp(
            r'INFO  \[http\] GET /api/v1/health 200 in \d+ms size=\d+ ip=127\.0\.0\.1 rid=e2e-1',
          ),
        ),
      );
      for (final step in [
        'shutting down: test',
        'closing HTTP server',
        'HTTP server closed in',
        'closing Postgres pool',
        'Postgres pool closed in',
        'shutdown complete in',
      ]) {
        expect(logs.text, contains(step));
      }
    });

    test(
      'runServerProcess: неверный конфиг → код 1 и понятная ошибка',
      () async {
        final code = await runServerProcess(
          environment: const {},
          setLogLevel: (_) {},
        );
        expect(code, 1);
        expect(
          logs.text,
          contains('ERROR [server] config invalid: DATABASE_URL is required'),
        );
      },
    );
  });
}
