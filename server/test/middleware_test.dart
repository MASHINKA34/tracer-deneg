import 'dart:convert';

import 'package:server/http/middleware.dart';
import 'package:shared/logging.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'support/test_support.dart';

Handler _pipeline(Handler handler) => const Pipeline()
    .addMiddleware(requestIdMiddleware())
    .addMiddleware(accessLogMiddleware())
    .addMiddleware(errorMiddleware())
    .addHandler(handler);

Request _get(String path, {Map<String, String>? headers}) => Request(
  'GET',
  Uri.parse('http://localhost$path?token=SECRET'),
  headers: headers,
);

void main() {
  late LogCapture logs;
  setUp(() => logs = LogCapture());

  group('X-Request-Id', () {
    test(
      'допустимый id из запроса возвращается и виден в логах обработчика',
      () async {
        String? seenInHandler;
        final handler = _pipeline((request) {
          seenInHandler = currentRequestId();
          return Response.ok('ok');
        });
        final response = await handler(
          _get('/x', headers: {'X-Request-Id': 'client-rid-1'}),
        );
        expect(response.headers['x-request-id'], 'client-rid-1');
        expect(seenInHandler, 'client-rid-1');
        expect(logs.text, contains('rid=client-rid-1'));
      },
    );

    test('нет заголовка — генерируется', () async {
      final response = await _pipeline((_) => Response.ok('ok'))(_get('/x'));
      expect(
        response.headers['x-request-id'],
        matches(RegExp(r'^[0-9a-f]{16}$')),
      );
    });

    test('недопустимый id заменяется новым', () async {
      final response = await _pipeline((_) => Response.ok('ok'))(
        _get('/x', headers: {'X-Request-Id': 'bad id with spaces'}),
      );
      expect(
        response.headers['x-request-id'],
        matches(RegExp(r'^[0-9a-f]{16}$')),
      );
      expect(logs.text, contains('invalid X-Request-Id replaced (length=18)'));
    });
  });

  group('лог запроса', () {
    test('метод, путь без query, статус, время, размер', () async {
      await _pipeline((_) => Response.ok('hello'))(
        _get('/api/v1/x', headers: {'X-Request-Id': 'r1'}),
      );
      expect(logs.lines.where((l) => l.contains(' INFO  [http] ')), [
        matches(RegExp(r'GET /api/v1/x 200 in \d+ms size=5 ip=- rid=r1$')),
      ]);
      expect(logs.text, isNot(contains('SECRET')));
    });
  });

  group('перехват ошибок', () {
    test('исключение → 500 с rid, в логе тип, сообщение и стек', () async {
      final response = await _pipeline((_) => throw StateError('boom'))(
        _get('/api/v1/fail', headers: {'X-Request-Id': 'r500'}),
      );
      expect(response.statusCode, 500);
      expect(
        response.headers['content-type'],
        'application/json; charset=utf-8',
      );
      expect(jsonDecode(await response.readAsString()), {
        'error': {
          'code': 'internal',
          'message': 'Внутренняя ошибка сервера',
          'rid': 'r500',
        },
      });
      expect(
        logs.text,
        contains(
          'ERROR [http] unhandled error in GET /api/v1/fail: StateError: Bad state: boom rid=r500',
        ),
      );
      // Описание ошибки уже в сообщении — отдельной строки error: нет,
      // полный стек есть.
      expect(logs.text, isNot(contains('  error: ')));
      expect(logs.text, contains('boom rid=r500\n  stack:\n    #0'));
      expect(
        logs.text,
        contains(RegExp(r'WARN  \[http\] GET /api/v1/fail 500 in \d+ms')),
      );
    });
  });
}
