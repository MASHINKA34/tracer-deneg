import 'dart:convert';

import 'package:server/client_errors/client_error_fields.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/auth_support.dart';
import 'support/test_support.dart';

int _bytes(String text) => utf8.encode(text).length;

void main() {
  group('limitHead / limitTail', () {
    test('текст в пределах лимита возвращается как есть', () {
      const text = 'короткий текст';
      expect(limitHead(text, _bytes(text)), same(text));
      expect(limitTail(text, _bytes(text)), same(text));
    });

    test('head: начало текста и отметка с полным размером, не больше лимита '
        'в байтах UTF-8', () {
      final text = 'а' * 1000;
      final cut = limitHead(text, 100);
      expect(_bytes(cut), lessThanOrEqualTo(100));
      expect(cut, endsWith('…[truncated, total 2000 bytes]'));
      expect(cut, startsWith('ааа'));
      expect(cut.replaceAll('…[truncated, total 2000 bytes]', ''), 'а' * 34);
    });

    test('tail: конец текста и отметка в начале', () {
      final text = '${'x' * 500}последняя строка';
      final cut = limitTail(text, 100);
      expect(_bytes(cut), lessThanOrEqualTo(100));
      expect(cut, startsWith('[truncated, total ${_bytes(text)} bytes]…'));
      expect(cut, endsWith('последняя строка'));
    });

    test('многобайтовые символы не разрезаются', () {
      final emoji = String.fromCharCodes([0x1F4A5]);
      final text = emoji * 100;
      for (final limit in [60, 61, 62, 63]) {
        final head = limitHead(text, limit);
        final tail = limitTail(text, limit);
        for (final cut in [head, tail]) {
          expect(_bytes(cut), lessThanOrEqualTo(limit));
          expect(utf8.decode(utf8.encode(cut)), cut);
          expect(cut.runes.where((r) => r == 0xFFFD), isEmpty);
        }
      }
    });

    test('utf8Length совпадает с utf8.encode, в том числе для одиночной '
        'суррогатной половины', () {
      for (final text in [
        '',
        'ascii',
        'кириллица',
        String.fromCharCodes([0x1F4A5, 0x41]),
        String.fromCharCode(0xD800),
      ]) {
        expect(utf8Length(text), _bytes(text), reason: text);
      }
    });
  });

  group('prepareClientError', () {
    test('message и stack — начало до maxClientErrorLogsBytes, logs — хвост; '
        'appVersion и deviceModel — короткие лимиты', () {
      final report = ClientErrorReport(
        appVersion: '1.0.0+${'9' * 100}',
        androidSdk: 36,
        deviceModel: 'P' * 200,
        kind: ClientErrorKind.crash,
        message: 'M${'m' * 300000}',
        stack: 'S${'s' * 300000}',
        logs: '${'l' * 300000}LAST',
      );
      final prepared = prepareClientError(report);
      expect(prepared.truncated, [
        'appVersion',
        'deviceModel',
        'message',
        'stack',
        'logs',
      ]);
      for (final value in [prepared.message, prepared.stack!, prepared.logs!]) {
        expect(_bytes(value), lessThanOrEqualTo(maxClientErrorLogsBytes));
        expect(_bytes(value), greaterThan(maxClientErrorLogsBytes - 64));
      }
      expect(prepared.message, startsWith('Mmmm'));
      expect(prepared.stack, startsWith('Ssss'));
      expect(prepared.logs, endsWith('lllLAST'));
      expect(_bytes(prepared.appVersion), lessThanOrEqualTo(64));
      expect(prepared.appVersion, startsWith('1.0.0+99'));
      expect(_bytes(prepared.deviceModel!), lessThanOrEqualTo(128));
      expect(prepared.nulReplaced, 0);
    });

    test('без обрезки поля не меняются и список truncated пуст', () {
      const report = ClientErrorReport(
        appVersion: '1.0.0+1',
        androidSdk: null,
        deviceModel: null,
        kind: ClientErrorKind.userReport,
        message: 'Отчёт пользователя',
      );
      final prepared = prepareClientError(report);
      expect(prepared.truncated, isEmpty);
      expect(prepared.message, 'Отчёт пользователя');
      expect(prepared.stack, isNull);
      expect(prepared.logs, isNull);
      expect(prepared.deviceModel, isNull);
    });
  });

  group('POST /client-errors: обрезка 200 КБ', () {
    late LogCapture logs;
    late AuthHarness api;

    setUp(() async {
      logs = LogCapture();
      api = await AuthHarness.start();
    });

    test('message, stack и logs по 300 КБ → 202, в базе каждое поле не '
        'больше 200 КБ: начало сообщения и стека, хвост логов', () async {
      final logsText = '${'строка лога\n' * 14500}самая последняя строка';
      final body = {
        'kind': 'crash',
        'appVersion': '1.0.0+1',
        'androidSdk': 36,
        'deviceModel': 'Pixel 7',
        'message': 'StateError: ${'m' * 300 * 1024}',
        'stack': '#0 main (package:app/main.dart:1:1)\n${'s' * 300 * 1024}',
        'logs': logsText,
      };
      expect(_bytes(logsText), greaterThan(300 * 1024));
      final size = _bytes(jsonEncode(body));
      expect(size, lessThan(1024 * 1024));

      final response = await api.post('/client-errors', body: body);
      expect(response.status, 202, reason: response.text);

      final rows = await api.db.execute(
        r'SELECT octet_length(message), octet_length(stack), '
        r'octet_length(logs), message, stack, logs FROM client_errors '
        r'WHERE id = $1::uuid',
        parameters: [response.json['id']],
      );
      final row = rows.single;
      for (final i in [0, 1, 2]) {
        expect(row[i]! as int, lessThanOrEqualTo(maxClientErrorLogsBytes));
        expect(row[i]! as int, greaterThan(maxClientErrorLogsBytes - 64));
      }
      expect(row[3], startsWith('StateError: mmm'));
      expect(row[3], endsWith('…[truncated, total ${300 * 1024 + 12} bytes]'));
      expect(row[4], startsWith('#0 main (package:app/main.dart:1:1)\nsss'));
      expect(
        row[5],
        startsWith('[truncated, total ${_bytes(logsText)} bytes]…'),
      );
      expect(row[5], endsWith('строка лога\nсамая последняя строка'));

      expect(
        logs.text,
        contains(
          RegExp(
            'client error received id=${response.json['id']} kind=crash '
            'appVersion=1\\.0\\.0\\+1 androidSdk=36 userId=none auth=none '
            'size=$size messageBytes=${row[0]} messageHash=[0-9a-f]{12} '
            'stackBytes=${row[1]} logsBytes=${row[2]} '
            'truncated=message,stack,logs in \\d+ms',
          ),
        ),
      );
      expect(logs.text, isNot(contains('самая последняя строка')));
      expect(logs.text, isNot(contains('mmmmmmmmmm')));
    });
  });
}
