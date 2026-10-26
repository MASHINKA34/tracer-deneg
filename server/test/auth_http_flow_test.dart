import 'dart:convert';
import 'dart:io';

import 'package:server/config/config.dart';
import 'package:server/server_app.dart';
import 'package:test/test.dart';

import 'support/test_support.dart';

void main() {
  late LogCapture logs;
  late RunningServer server;
  late HttpClient client;

  setUp(() async {
    logs = LogCapture();
    server = await startServer(
      ServerConfig.load(
        environment: {
          'HOST': '127.0.0.1',
          'PORT': '0',
          'DATABASE_URL': await createScratchDatabase(),
          'JWT_SECRET': 'http-flow-secret-0123456789-abcdefgh',
          'INVITE_CODE_SECRET': 'invite-code-secret-0123456789-abcdef',
        },
      ),
      dbConnectAttempts: 1,
    );
    client = HttpClient();
    addTearDown(() async {
      client.close(force: true);
      await server.shutdown('test');
    });
  });

  Future<(int, Map<String, Object?>?)> post(
    String path, {
    Object? body,
    String? bearer,
  }) async {
    final request = await client.post('127.0.0.1', server.port, '/api/v1$path');
    request.headers.contentType = ContentType.json;
    if (bearer != null) request.headers.set('authorization', 'Bearer $bearer');
    if (body != null) request.write(jsonEncode(body));
    final response = await request.close();
    final text = await response.transform(utf8.decoder).join();
    return (
      response.statusCode,
      text.isEmpty ? null : jsonDecode(text) as Map<String, Object?>,
    );
  }

  test(
    'по HTTP: регистрация 201 → вход → refresh → logout 204 → refresh 401',
    () async {
      final (registerStatus, registered) = await post(
        '/auth/register',
        body: {
          'login': 'Flow.User',
          'displayName': 'Поток',
          'password': 'flow-pass-1',
          'deviceName': 'curl',
        },
      );
      expect(registerStatus, 201);
      expect(
        registered!.keys,
        unorderedEquals([
          'user',
          'accessToken',
          'refreshToken',
          'recoveryCode',
        ]),
      );
      expect((registered['user']! as Map)['login'], 'flow.user');

      final (loginStatus, login) = await post(
        '/auth/login',
        body: {
          'login': 'FLOW.USER',
          'password': 'flow-pass-1',
          'deviceName': 'curl',
        },
      );
      expect(loginStatus, 200);

      final (refreshStatus, refreshed) = await post(
        '/auth/refresh',
        body: {'refreshToken': login!['refreshToken']},
      );
      expect(refreshStatus, 200);

      final (logoutStatus, logoutBody) = await post(
        '/auth/logout',
        bearer: refreshed!['accessToken']! as String,
      );
      expect(logoutStatus, 204);
      expect(logoutBody, isNull);

      final (afterStatus, after) = await post(
        '/auth/refresh',
        body: {'refreshToken': refreshed['refreshToken']},
      );
      expect(afterStatus, 401);
      expect(after, {
        'error': {
          'code': 'session_expired',
          'message': 'Сессия закончилась, войди снова',
        },
      });

      final (otherStatus, _) = await post(
        '/auth/refresh',
        body: {'refreshToken': registered['refreshToken']},
      );
      expect(otherStatus, 200);
      int at(String text) =>
          logs.lines.indexWhere((line) => line.contains(text));
      expect(
        at('auth: warming up argon2id'),
        greaterThan(at('migrations: applied')),
      );
      expect(at('HTTP server listening'), greaterThan(at('auth ready')));

      expect(
        logs.text,
        contains(
          RegExp(
            r'INFO  \[server\] auth ready: argon2id m=19456,t=2,p=1 hash in \d+ms maxConcurrent=4 access=15m refresh=90d',
          ),
        ),
      );
      expect(
        logs.text,
        contains(
          RegExp(r'INFO  \[http\] POST /api/v1/auth/register 201 in \d+ms'),
        ),
      );
      expect(
        logs.text,
        contains(
          RegExp(r'INFO  \[http\] POST /api/v1/auth/logout 204 in \d+ms'),
        ),
      );
      expect(
        logs.text,
        contains(
          RegExp(r'INFO  \[http\] POST /api/v1/auth/refresh 401 in \d+ms'),
        ),
      );
    },
  );
}
