import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milionchik/data/api/api_client.dart';
import 'package:milionchik/data/api/api_config.dart';
import 'package:milionchik/data/api/api_error_text.dart';
import 'package:milionchik/data/api/api_exception.dart';
import 'package:milionchik/l10n/app_localizations.dart';
import 'package:shared/shared.dart';

import 'fake_api_adapter.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('ru'));
  final config = ApiConfig.resolve(define: '', debugBuild: true);
  late LogCapture logs;

  setUp(() => logs = LogCapture());
  tearDown(() => logs.dispose());

  Future<ApiException> failure(
    FakeHandler handler, {
    String path = '/budgets',
  }) async {
    final api = ApiClient(
      config: config,
      adapter: FakeApiAdapter(handler),
      newRequestId: () => 'ridmapping0000001',
    );
    try {
      await api.post(path, body: const {'id': 'b1'}, auth: false);
    } on ApiException catch (e) {
      return e;
    }
    fail('request did not fail');
  }

  test('ошибка сервера {error: {code, message}} - ApiErrorResponse с кодом, '
      'статусом и rid, текст из ARB', () async {
    final e = await failure(
      (call) => FakeReply.error(409, 'conflict', 'Бюджет с таким id уже есть'),
    );

    expect(e, isA<ApiErrorResponse>());
    final response = e as ApiErrorResponse;
    expect(response.statusCode, 409);
    expect(response.code, ApiErrorCode.conflict);
    expect(response.error.message, 'Бюджет с таким id уже есть');
    expect(response.requestId, 'ridmapping0000001');
    expect(response.path, '/api/v1/budgets');
    expect(
      apiErrorText(l10n, e),
      'Данные уже изменились. Обнови и попробуй снова',
    );
  });

  test('bad_credentials - свой текст, не текст сервера', () async {
    final e = await failure(
      (call) => FakeReply.error(401, 'bad_credentials', 'server-text-marker'),
      path: '/auth/login',
    );

    expect((e as ApiErrorResponse).code, ApiErrorCode.badCredentials);
    expect(apiErrorText(l10n, e), 'Неверный логин или пароль');
  });

  test('неизвестный код (валидация) - сообщение сервера', () async {
    final e = await failure(
      (call) => FakeReply.error(
        400,
        'login_too_short',
        'Логин слишком короткий: нужно от 3 символов',
      ),
    );

    expect((e as ApiErrorResponse).code, isNull);
    expect(e.error.code, 'login_too_short');
    expect(
      apiErrorText(l10n, e),
      'Логин слишком короткий: нужно от 3 символов',
    );
  });

  test('500 с кодом internal и 503 без обёртки - ApiServerFailure', () async {
    final internal = await failure(
      (call) => FakeReply.json(500, {
        'error': {
          'code': 'internal',
          'message': 'Внутренняя ошибка сервера',
          'rid': 'x',
        },
      }),
    );
    final degraded = await failure(
      (call) => FakeReply.json(503, {'status': 'degraded', 'db': 'error'}),
    );

    expect(internal, isA<ApiServerFailure>());
    expect((internal as ApiServerFailure).statusCode, 500);
    expect(internal.error?.code, 'internal');
    expect((degraded as ApiServerFailure).statusCode, 503);
    expect(degraded.error, isNull);
    expect(
      apiErrorText(l10n, internal),
      'На сервере что-то сломалось. Попробуй позже',
    );
  });

  test('4xx без обёртки и 200 не JSON - ApiBadResponse', () async {
    final html = await failure(
      (call) => const FakeReply(404, '<html>nginx</html>'),
    );
    final notJson = await failure((call) => const FakeReply(200, 'not json'));

    expect(html, isA<ApiBadResponse>());
    expect((html as ApiBadResponse).statusCode, 404);
    expect(notJson, isA<ApiBadResponse>());
    expect((notJson as ApiBadResponse).statusCode, 200);
    expect(
      apiErrorText(l10n, notJson),
      'Сервер ответил непонятно. Попробуй позже',
    );
  });

  test('нет сети - ApiNetworkFailure(connection) с причиной', () async {
    final e = await failure(
      (call) => throw const SocketException(
        'Connection refused',
        osError: OSError('refused', 111),
      ),
    );

    expect(e, isA<ApiNetworkFailure>());
    expect((e as ApiNetworkFailure).problem, ApiNetworkProblem.connection);
    expect(e.toString(), contains('cause=SocketException: Connection refused'));
    expect(e.toString(), contains('errno = 111'));
    expect(
      apiErrorText(l10n, e),
      'Нет связи с сервером. Проверь интернет и попробуй ещё раз',
    );
  });

  test(
    'таймаут подключения и ответа - ApiTimeout с фазой и пределом',
    () async {
      final connect = await failure(
        (call) => throw DioException.connectionTimeout(
          timeout: apiConnectTimeout,
          requestOptions: call.options,
        ),
      );
      final receive = await failure(
        (call) => throw DioException.receiveTimeout(
          timeout: apiReceiveTimeout,
          requestOptions: call.options,
        ),
      );

      expect((connect as ApiTimeout).phase, ApiTimeoutPhase.connect);
      expect(connect.limit, const Duration(seconds: 10));
      expect((receive as ApiTimeout).phase, ApiTimeoutPhase.receive);
      expect(receive.limit, const Duration(seconds: 30));
      expect(
        apiErrorText(l10n, receive),
        'Сервер долго не отвечает. Попробуй ещё раз',
      );
      expect(logs.text, contains('POST /api/v1/budgets failed in '));
      expect(
        logs.text,
        contains('receive timeout after 30s rid=ridmapping0000001'),
      );
    },
  );

  test('у каждого известного кода свой текст из ARB', () {
    for (final code in ApiErrorCode.values) {
      final text = apiErrorCodeText(l10n, code);
      expect(text.trim(), isNotEmpty, reason: code.code);
    }
    expect(
      apiErrorCodeText(l10n, ApiErrorCode.sessionExpired),
      'Сессия закончилась, войди снова',
    );
  });
}
