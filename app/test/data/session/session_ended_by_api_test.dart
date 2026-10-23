import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:milionchik/data/api/api_config.dart';
import 'package:milionchik/data/api/api_exception.dart';
import 'package:milionchik/data/api/api_providers.dart';
import 'package:milionchik/data/api/token_store.dart';
import 'package:milionchik/data/session/session.dart';
import 'package:milionchik/data/session/session_providers.dart';
import 'package:milionchik/data/session/session_state.dart';
import 'package:milionchik/data/session/session_store.dart';

import '../provider_harness.dart';
import 'fake_secure_values.dart';

const _session = Session(
  user: SessionUser(
    userId: 'user-server-77',
    login: 'enot_login',
    displayName: 'Енот',
  ),
  tokens: AuthTokens(
    accessToken: 'ACCESS-lima-kilo-juliett-india',
    refreshToken: 'REFRESH-hotel-golf-foxtrot-echo',
  ),
);

void main() {
  late HttpServer server;
  final paths = <String>[];

  setUp(() async {
    paths.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      paths.add('${request.method} ${request.uri.path}');
      await request.drain<void>();
      final code = request.uri.path.endsWith('/auth/refresh')
          ? 'session_expired'
          : 'unauthorized';
      request.response
        ..statusCode = 401
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            'error': {'code': code, 'message': 'нет'},
          }),
        );
      await request.response.close();
    });
  });

  tearDown(() => server.close(force: true));

  test('refresh отклонён сервером → состояние сессии «истекла» '
      '(refreshRejected), токены остаются в хранилище', () async {
    final values = FakeSecureValues();
    final h = ProviderHarness(
      overrides: [
        secureValuesProvider.overrideWithValue(values),
        apiConfigProvider.overrideWithValue(
          ApiConfig(
            baseUrl: Uri.parse('http://127.0.0.1:${server.port}/api/v1'),
            fromDefine: true,
          ),
        ),
      ],
    );
    await h.read(sessionProvider.notifier).save(_session);

    await expectLater(
      h.read(apiClientProvider).get('/me'),
      throwsA(isA<ApiSessionExpired>()),
    );
    await pumpEventQueue();

    expect(paths, ['GET /api/v1/me', 'POST /api/v1/auth/refresh']);
    final state = h.read(sessionProvider);
    expect(state, isA<SessionEnded>());
    expect((state as SessionEnded).reason, SessionEndReason.refreshRejected);
    expect(state.userId, 'user-server-77');
    expect(values.data.keys, {SessionStore.userKey, SessionStore.tokensKey});
  });
}
