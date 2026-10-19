import 'dart:convert';

import 'package:shared/logging.dart';
import 'package:test/test.dart';

void main() {
  group('maskLogin', () {
    test('первые 2 символа и ***', () {
      expect(maskLogin('anna'), 'an***');
      expect(maskLogin('ann'), 'an***');
      expect(maskLogin('дмитрий'), 'дм***');
    });

    test('короткий логин не раскрывается', () {
      expect(maskLogin('ab'), '***');
      expect(maskLogin('a'), '***');
    });

    test('пустой и отсутствующий', () {
      expect(maskLogin(''), '<empty>');
      expect(maskLogin(null), '<none>');
    });
  });

  group('maskInviteCode', () {
    test('код не виден', () {
      expect(maskInviteCode('MLN-7K2Q'), 'MLN-****');
      expect(maskInviteCode('mln7k2q'), 'MLN-****');
    });

    test('пустой и отсутствующий', () {
      expect(maskInviteCode(''), '<empty>');
      expect(maskInviteCode(null), '<none>');
    });
  });

  group('maskToken', () {
    test('только длина', () {
      expect(maskToken('a' * 43), '***(43)');
      expect(maskToken('x'), '***(1)');
    });

    test('пустой и отсутствующий', () {
      expect(maskToken(''), '<empty>');
      expect(maskToken(null), '<none>');
    });
  });

  group('truncateBody', () {
    test('короткое тело не меняется', () {
      const body = '{"ok":true}';
      expect(truncateBody(body), body);
      expect(truncateBody('a' * logBodyLimitBytes), 'a' * logBodyLimitBytes);
    });

    test('длинное тело обрезается до 2 КБ с полным размером', () {
      final body = 'a' * 5000;
      final result = truncateBody(body);
      expect(result, '${'a' * 2048}…[truncated, total 5000 bytes]');
    });

    test('режет по границе символа и считает байты UTF-8', () {
      // «ё» — 2 байта: в 5 байт помещаются 2 символа, полный размер 10 байт.
      final result = truncateBody('ёёёёё', maxBytes: 5);
      expect(result, 'ёё…[truncated, total 10 bytes]');
      expect(utf8.encode(result.split('…').first).length, lessThanOrEqualTo(5));
    });

    test('эмодзи (4 байта) не разрезается пополам', () {
      final result = truncateBody('🎃🎃🎃', maxBytes: 6);
      expect(result, '🎃…[truncated, total 12 bytes]');
    });
  });
}
