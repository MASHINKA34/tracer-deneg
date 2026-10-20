import 'dart:math';

import 'package:shared/shared.dart';
import 'package:test/test.dart';

final _recovery = RegExp(
  r'^[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}-'
  r'[0-9A-HJKMNP-TV-Z]{4}$',
);
final _invite = RegExp(r'^MLN-[0-9A-HJKMNP-TV-Z]{4}$');

void main() {
  test('алфавит Crockford Base32: 32 символа без I, L, O, U', () {
    expect(crockfordAlphabet, hasLength(32));
    expect(crockfordAlphabet.split('').toSet(), hasLength(32));
    for (final c in ['I', 'L', 'O', 'U']) {
      expect(crockfordAlphabet.contains(c), isFalse);
    }
  });

  group('код восстановления', () {
    test('генерация: XXXX-XXXX-XXXX из алфавита', () {
      final random = Random(1);
      for (var i = 0; i < 200; i++) {
        final code = generateRecoveryCode(random);
        expect(code, matches(_recovery));
        expect(normalizeRecoveryCode(code), code.replaceAll('-', ''));
      }
    });

    test('одинаковый источник случайности — одинаковый код', () {
      expect(
        generateRecoveryCode(Random(42)),
        generateRecoveryCode(Random(42)),
      );
    });

    test('используются все символы алфавита', () {
      final random = Random(7);
      final seen = <String>{};
      for (var i = 0; i < 300; i++) {
        seen.addAll(generateRecoveryCode(random).replaceAll('-', '').split(''));
      }
      expect(seen, crockfordAlphabet.split('').toSet());
    });

    test('ввод без учёта регистра, дефисов и пробелов', () {
      expect(normalizeRecoveryCode('abcd-efgh-jkmn'), 'ABCDEFGHJKMN');
      expect(normalizeRecoveryCode(' ABCD EFGH JKMN '), 'ABCDEFGHJKMN');
      expect(normalizeRecoveryCode('ABCDEFGHJKMN'), 'ABCDEFGHJKMN');
    });

    test('O → 0, I и L → 1', () {
      expect(normalizeRecoveryCode('oooo-iiii-llll'), '000011111111');
    });

    test('неверный код — null', () {
      expect(normalizeRecoveryCode('ABCD-EFGH-JKMU'), isNull);
      expect(normalizeRecoveryCode('ABCD-EFGH-JKM'), isNull);
      expect(normalizeRecoveryCode('ABCD-EFGH-JKMNP'), isNull);
      expect(normalizeRecoveryCode('ABCD-EFGH-JKM!'), isNull);
      expect(normalizeRecoveryCode(''), isNull);
    });

    test('показ группами', () {
      expect(formatRecoveryCode('abcdefghjkmn'), 'ABCD-EFGH-JKMN');
      expect(() => formatRecoveryCode('abc'), throwsFormatException);
    });

    test('маска для лога', () {
      expect(maskRecoveryCode('ABCD-EFGH-JKMN'), '****-****-****');
      expect(maskRecoveryCode(''), '<empty>');
      expect(maskRecoveryCode(null), '<none>');
    });
  });

  group('код приглашения', () {
    test('генерация: MLN-XXXX', () {
      final random = Random(3);
      for (var i = 0; i < 100; i++) {
        final code = generateInviteCode(random);
        expect(code, matches(_invite));
        expect(normalizeInviteCode(code), code);
      }
    });

    test('ввод с префиксом и без, регистр, дефисы и пробелы не важны', () {
      for (final input in [
        'MLN-48K2',
        'mln48k2',
        '48k2',
        'MLN 48K2',
        ' 48-K2 ',
        'mln-48-k2',
      ]) {
        expect(normalizeInviteCode(input), 'MLN-48K2', reason: input);
      }
    });

    test('Crockford-замены в теле кода', () {
      expect(normalizeInviteCode('MLN-O1IL'), 'MLN-0111');
      // Четыре символа без префикса — это тело кода.
      expect(normalizeInviteCode('mlno'), 'MLN-M1N0');
    });

    test('неверный код — null', () {
      expect(normalizeInviteCode('MLN-48KU'), isNull);
      expect(normalizeInviteCode('MLN-48K'), isNull);
      expect(normalizeInviteCode('XYZ48K2'), isNull);
      expect(normalizeInviteCode('48K22'), isNull);
      expect(normalizeInviteCode(''), isNull);
    });

    test('маска для лога', () {
      expect(maskInviteCode('MLN-48K2'), 'MLN-****');
    });
  });
}
