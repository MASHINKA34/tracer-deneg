import 'dart:convert';

import 'package:shared/shared.dart';
import 'package:test/test.dart';

void main() {
  group('ApiError', () {
    test('формат {"error": {"code", "message"}}', () {
      final error = ApiError.of(
        ApiErrorCode.loginTaken,
        'Такой логин уже занят',
      );
      expect(error.toJson(), {
        'error': {'code': 'login_taken', 'message': 'Такой логин уже занят'},
      });
      final parsed = ApiError.fromJson(jsonDecode(jsonEncode(error.toJson())));
      expect(parsed, error);
      expect(parsed.knownCode, ApiErrorCode.loginTaken);
      expect(parsed.hashCode, error.hashCode);
      expect(parsed.toString(), 'ApiError(login_taken: Такой логин уже занят)');
    });

    test('коды валидации и неизвестные коды', () {
      final validation = ApiError(
        code: ValidationError.loginTooShort.code,
        message: 'Логин короче 3 символов',
      );
      expect(validation.knownCode, isNull);
      expect(
        ValidationError.fromCode(validation.code),
        ValidationError.loginTooShort,
      );
      expect(ApiErrorCode.fromCode('teapot'), isNull);
    });

    test('без обёртки error — ошибка разбора', () {
      expect(
        () => ApiError.fromJson({'code': 'x', 'message': 'y'}),
        throwsFormatException,
      );
    });

    test('коды из спецификации, уникальные, в snake_case', () {
      final codes = ApiErrorCode.values.map((c) => c.code).toList();
      expect(codes.toSet(), hasLength(codes.length));
      expect(
        codes,
        containsAll([
          'login_taken',
          'bad_credentials',
          'too_many_attempts',
          'invite_not_found',
        ]),
      );
      for (final code in codes) {
        expect(code, matches(RegExp(r'^[a-z]+(_[a-z]+)*$')));
        expect(ApiErrorCode.fromCode(code)!.code, code);
      }
      // Коды API и валидации не пересекаются.
      final validation = ValidationError.values.map((v) => v.code).toSet();
      expect(codes.toSet().intersection(validation), isEmpty);
    });
  });
}
