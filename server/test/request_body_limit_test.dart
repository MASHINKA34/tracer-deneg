import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:server/config/config.dart';
import 'package:server/limits/request_limits.dart';
import 'package:server/server_app.dart';
import 'package:test/test.dart';

import 'support/limits_support.dart';
import 'support/test_support.dart';

const _limit = 1024 * 1024;

String _refreshBodyOf(int size) {
  const head = '{"refreshToken":"';
  const tail = '"}';
  return '$head${'r' * (size - head.length - tail.length)}$tail';
}

class _CountingBody {
  _CountingBody(this.total);

  static const int chunk = 64 * 1024;

  final int total;
  int emitted = 0;

  Stream<List<int>> stream() async* {
    while (emitted < total) {
      final size = total - emitted < chunk ? total - emitted : chunk;
      emitted += size;
      yield List<int>.filled(size, 0x20);
    }
  }
}

void main() {
  late LogCapture logs;

  setUp(() => logs = LogCapture());

  test('лимит тела — 1 МБ', () {
    expect(maxRequestBodyBytes, _limit);
  });

  group('через обработчик', () {
    late LimitsHarness api;

    setUp(() async => api = await LimitsHarness.start());

    test('ровно 1 МБ доходит до обработчика, 1 МБ + 1 байт → 413 '
        'payload_too_large', () async {
      final exact = await api.post(
        '/auth/refresh',
        rawBody: _refreshBodyOf(_limit),
      );
      expect(exact.status, 401, reason: '$exact');
      expect(exact.errorCode, 'session_expired');

      final over = await api.post(
        '/auth/refresh',
        rawBody: _refreshBodyOf(_limit + 1),
      );
      expect(over.status, 413, reason: '$over');
      expect(over.errorCode, 'payload_too_large');
      expect(
        (over.json['error']! as Map<String, Object?>)['message'],
        'Слишком большой запрос: не больше 1 МБ',
      );
      expect(
        logs.lines,
        contains(
          allOf(
            contains('WARN'),
            contains(
              '[limits] request body too large POST /api/v1/auth/refresh '
              'ip=$defaultTestIp contentLength=${_limit + 1} limit=$_limit '
              '→ 413 without reading',
            ),
          ),
        ),
      );
    });

    test('без Content-Length чтение обрывается на лимите → 413', () async {
      for (final path in ['/auth/login', '/auth/refresh']) {
        final body = _CountingBody(5 * _limit);
        final response = await api.post(path, rawBody: body.stream());
        expect(response.status, 413, reason: '$path: $response');
        expect(response.errorCode, 'payload_too_large');
        expect(body.emitted, lessThanOrEqualTo(_limit + _CountingBody.chunk));
      }
      expect(
        logs.text,
        contains(
          '[limits] request body too large POST /api/v1/auth/login '
          'ip=$defaultTestIp contentLength=none read=${_limit + 64 * 1024} '
          'limit=$_limit → 413, rest of body not read',
        ),
      );
    });

    test('без Content-Length тело до 1 МБ доходит до обработчика', () async {
      final response = await api.post(
        '/auth/refresh',
        rawBody: Stream.value(utf8.encode(_refreshBodyOf(_limit))),
      );
      expect(response.status, 401, reason: '$response');
      expect(response.errorCode, 'session_expired');
    });

    test('без Content-Length обработчик не читал тело (401 без токена) — '
        'остаток вычитывается только до лимита', () async {
      final body = _CountingBody(5 * _limit);
      final response = await api.send('PATCH', '/me', rawBody: body.stream());
      expect(response.status, 401, reason: '$response');
      expect(response.errorCode, 'unauthorized');

      await waitUntil(() => body.emitted > _limit);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(body.emitted, _limit + _CountingBody.chunk);
      expect(
        logs.lines,
        contains(
          allOf(
            contains('WARN'),
            contains(
              '[limits] request body too large PATCH /api/v1/me '
              'ip=$defaultTestIp contentLength=none read=${_limit + _CountingBody.chunk} '
              'limit=$_limit → body unread by handler (status=401)',
            ),
          ),
        ),
      );
    });
  });

  group('по настоящему HTTP', () {
    late RunningServer server;

    setUp(() async {
      server = await startServer(
        ServerConfig.load(
          environment: {
            'HOST': '127.0.0.1',
            'PORT': '0',
            'DATABASE_URL': await createScratchDatabase(),
            'JWT_SECRET': 'body-limit-secret-0123456789-abcdefgh',
            'INVITE_CODE_SECRET': 'invite-code-secret-0123456789-abcdef',
          },
        ),
        dbConnectAttempts: 1,
      );
      addTearDown(() => server.shutdown('test'));
    });

    Future<String> exchange(String head, List<int> body) async {
      final socket = await Socket.connect('127.0.0.1', server.port);
      socket.add(utf8.encode(head));
      socket.add(body);
      await socket.flush();
      final text = await utf8.decoder
          .bind(socket)
          .join()
          .timeout(const Duration(seconds: 10));
      socket.destroy();
      return text;
    }

    test(
      'Content-Length 1 МБ + 1 байт → 413 сразу, тело не отправляли',
      () async {
        final response = await exchange(
          'POST /api/v1/auth/login HTTP/1.1\r\n'
          'Host: 127.0.0.1\r\n'
          'Content-Type: application/json\r\n'
          'Content-Length: ${_limit + 1}\r\n'
          '\r\n',
          utf8.encode('{"login":'),
        );
        expect(response, startsWith('HTTP/1.1 413'));
        expect(response, contains('"code":"payload_too_large"'));
      },
    );

    test('chunked больше 1 МБ → 413, сервер дальше отвечает', () async {
      final body = <int>[];
      for (final size in [256 * 1024, 256 * 1024, 256 * 1024, 256 * 1024, 1]) {
        body
          ..addAll(utf8.encode('${size.toRadixString(16)}\r\n'))
          ..addAll(List<int>.filled(size, 0x20))
          ..addAll(utf8.encode('\r\n'));
      }
      final response = await exchange(
        'POST /api/v1/auth/refresh HTTP/1.1\r\n'
        'Host: 127.0.0.1\r\n'
        'Content-Type: application/json\r\n'
        'Transfer-Encoding: chunked\r\n'
        '\r\n',
        body,
      );
      expect(response, startsWith('HTTP/1.1 413'));
      expect(response.toLowerCase(), contains('connection: close'));
      expect(response, contains('"code":"payload_too_large"'));

      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final health = await (await client.get(
        '127.0.0.1',
        server.port,
        '/api/v1/health',
      )).close();
      expect(health.statusCode, 200);
      await health.drain<void>();
    });
  });
}
