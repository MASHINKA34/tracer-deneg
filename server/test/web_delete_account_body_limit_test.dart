import 'dart:convert';
import 'dart:io';

import 'package:server/config/config.dart';
import 'package:server/server_app.dart';
import 'package:test/test.dart';

import 'support/limits_support.dart';
import 'support/test_support.dart';
import 'support/web_support.dart';

const _limit = 1024 * 1024;
const _chunk = 64 * 1024;
const _right = 'Vera-Right-Pass-Sigma';
const _formHead = 'login=vera&password=$_right&pad=';

class _FormStream {
  _FormStream(this.total);

  final int total;
  int emitted = 0;

  Stream<List<int>> stream() async* {
    final head = utf8.encode(_formHead);
    while (emitted < total) {
      final size = total - emitted < _chunk ? total - emitted : _chunk;
      final chunk = List<int>.filled(size, 0x61);
      if (emitted == 0) chunk.setRange(0, head.length, head);
      emitted += size;
      yield chunk;
    }
  }
}

void main() {
  late LogCapture logs;

  setUp(() => logs = LogCapture());

  group('через обработчик', () {
    late WebHarness web;

    setUp(() async {
      web = await WebHarness.start();
      expect((await web.register('vera', _right)).status, 201);
      logs.clear();
    });

    Future<bool> veraDeleted() async =>
        await web.count(
          "SELECT count(*)::int FROM users WHERE login = 'vera' "
          'AND deleted_at IS NOT NULL',
        ) ==
        1;

    void expectPayloadTooLarge(WebPage page) {
      expect(page.status, 413, reason: '$page');
      expect(page.headers['connection'], 'close');
      final json = jsonDecode(page.html) as Map<String, Object?>;
      final error = json['error']! as Map<String, Object?>;
      expect(error['code'], 'payload_too_large');
      expect(page.html, isNot(contains('Что-то пошло не так')));
    }

    test('тело-поток без Content-Length больше 1 МБ → 413 payload_too_large, '
        'warn [limits], без ERROR и 500-страницы, аккаунт цел', () async {
      final body = _FormStream(2 * _limit);

      final page = await web.postForm(
        '/delete-account',
        rawBody: body.stream(),
      );

      expectPayloadTooLarge(page);
      expect(body.emitted, lessThanOrEqualTo(_limit + _chunk));
      expect(await veraDeleted(), isFalse);
      expect(web.limits.loginFailures.count('vera'), 0);
      expect(
        logs.lines,
        contains(
          allOf(
            contains('WARN'),
            contains(
              '[limits] request body too large POST /delete-account '
              'ip=$defaultTestIp contentLength=none read=${_limit + _chunk} '
              'limit=$_limit → 413, rest of body not read',
            ),
          ),
        ),
      );
      expect(logs.text, contains('POST /delete-account 413'));
      expect(logs.text, isNot(contains('ERROR')));
      expect(logs.text, isNot(contains('web page failed')));
    });

    test('тело с Content-Length больше 1 МБ → 413 без чтения тела, '
        'без ERROR', () async {
      final form = '$_formHead${'a' * _limit}';

      final page = await web.postForm('/delete-account', rawBody: form);

      expectPayloadTooLarge(page);
      expect(await veraDeleted(), isFalse);
      expect(
        logs.lines,
        contains(
          allOf(
            contains('WARN'),
            contains(
              '[limits] request body too large POST /delete-account '
              'ip=$defaultTestIp contentLength=${form.length} '
              'limit=$_limit → 413 without reading',
            ),
          ),
        ),
      );
      expect(logs.text, isNot(contains('ERROR')));
    });

    test('тело-поток без Content-Length до 1 МБ доходит до формы и удаляет '
        'аккаунт', () async {
      final page = await web.postForm(
        '/delete-account',
        rawBody: _FormStream(_limit).stream(),
      );

      expect(page.status, 200, reason: '$page');
      expect(page.text, contains('Аккаунт удалён'));
      expect(await veraDeleted(), isTrue);
    });
  });

  group('по настоящему HTTP', () {
    test('chunked больше 1 МБ на POST /delete-account → 413, без ERROR, '
        'сервер дальше отвечает', () async {
      final server = await startServer(
        ServerConfig.load(
          environment: {
            'HOST': '127.0.0.1',
            'PORT': '0',
            'DATABASE_URL': await createScratchDatabase(),
            'JWT_SECRET': 'web-body-limit-secret-0123456789-abcdef',
            'INVITE_CODE_SECRET': 'invite-code-secret-0123456789-abcdef',
          },
        ),
        dbConnectAttempts: 1,
      );
      addTearDown(() => server.shutdown('test'));

      final body = <int>[];
      for (final size in [256 * 1024, 256 * 1024, 256 * 1024, 256 * 1024, 1]) {
        body
          ..addAll(utf8.encode('${size.toRadixString(16)}\r\n'))
          ..addAll(List<int>.filled(size, 0x61))
          ..addAll(utf8.encode('\r\n'));
      }
      body.addAll(utf8.encode('0\r\n\r\n'));
      final socket = await Socket.connect('127.0.0.1', server.port);
      socket
        ..add(
          utf8.encode(
            'POST /delete-account HTTP/1.1\r\n'
            'Host: 127.0.0.1\r\n'
            'Content-Type: application/x-www-form-urlencoded\r\n'
            'Transfer-Encoding: chunked\r\n'
            '\r\n',
          ),
        )
        ..add(body);
      await socket.flush();
      final response = await utf8.decoder
          .bind(socket)
          .join()
          .timeout(const Duration(seconds: 10));
      socket.destroy();

      expect(response, startsWith('HTTP/1.1 413'));
      expect(response, contains('"code":"payload_too_large"'));
      expect(response, isNot(contains('Что-то пошло не так')));
      expect(
        logs.lines,
        contains(
          allOf(
            contains('WARN'),
            contains(
              '[limits] request body too large POST /delete-account '
              'ip=127.0.0.1 contentLength=none',
            ),
            contains('→ 413, rest of body not read'),
          ),
        ),
      );
      expect(logs.text, isNot(contains('ERROR')));

      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final page = await (await client.get(
        '127.0.0.1',
        server.port,
        '/delete-account',
      )).close();
      expect(page.statusCode, 200);
      await page.drain<void>();
    });
  });
}
