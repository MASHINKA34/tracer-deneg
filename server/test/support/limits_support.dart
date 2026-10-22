import 'dart:convert';
import 'dart:io';

import 'package:server/auth/auth_service.dart';
import 'package:server/auth/password_hasher.dart';
import 'package:server/auth/tokens.dart';
import 'package:server/db/database.dart';
import 'package:server/db/migrator.dart';
import 'package:server/http/router.dart';
import 'package:server/limits/request_limits.dart';
import 'package:server/limits/trusted_proxies.dart';
import 'package:shelf/shelf.dart';

import 'auth_support.dart';
import 'test_support.dart';

const defaultTestIp = '198.51.100.1';

class FakeClock {
  DateTime current = DateTime.utc(2026, 10, 23, 12);

  DateTime now() => current;

  void advance(Duration step) => current = current.add(step);
}

class FakeConnectionInfo implements HttpConnectionInfo {
  FakeConnectionInfo(String ip) : remoteAddress = InternetAddress(ip);

  @override
  final InternetAddress remoteAddress;

  @override
  int get remotePort => 50123;

  @override
  int get localPort => 8080;
}

class LimitsHarness {
  LimitsHarness._(this.db, this.limits, this.clock, this.handler);

  static Future<LimitsHarness> start({
    TrustedProxies trustedProxies = TrustedProxies.none,
  }) async {
    final db = await openScratchDatabase();
    await Migrator(db, directory: Directory('migrations')).run();
    final clock = FakeClock();
    final limits = RequestLimits(
      trustedProxies: trustedProxies,
      now: clock.now,
    );
    final auth = AuthService(
      db: db,
      hasher: PasswordHasher(),
      accessTokens: AccessTokens(testJwtSecret),
    );
    return LimitsHarness._(
      db,
      limits,
      clock,
      buildHandler(db: db, auth: auth, limits: limits),
    );
  }

  final Database db;
  final RequestLimits limits;
  final FakeClock clock;
  final Handler handler;

  Future<ApiResponse> send(
    String method,
    String path, {
    Object? body,
    Object? rawBody,
    String? ip = defaultTestIp,
    Map<String, String> headers = const {},
  }) async {
    final response = await handler(
      Request(
        method,
        Uri.parse('http://localhost/api/v1$path'),
        body: rawBody ?? (body == null ? '' : jsonEncode(body)),
        headers: {'content-type': 'application/json', ...headers},
        context: {
          if (ip != null) 'shelf.io.connection_info': FakeConnectionInfo(ip),
        },
      ),
    );
    return ApiResponse(
      response.statusCode,
      response.headers,
      await response.readAsString(),
    );
  }

  Future<ApiResponse> post(
    String path, {
    Object? body,
    Object? rawBody,
    String? ip = defaultTestIp,
    Map<String, String> headers = const {},
  }) => send(
    'POST',
    path,
    body: body,
    rawBody: rawBody,
    ip: ip,
    headers: headers,
  );

  Future<ApiResponse> register(String login, {String? ip}) => post(
    '/auth/register',
    body: {
      'login': login,
      'displayName': 'Тест',
      'password': 'right-pass-$login',
      'deviceName': 'Pixel 7',
    },
    ip: ip ?? '198.51.100.250',
  );

  Future<ApiResponse> login(String login, String password, {String? ip}) =>
      post(
        '/auth/login',
        body: {'login': login, 'password': password, 'deviceName': 'Pixel 7'},
        ip: ip ?? defaultTestIp,
      );

  Future<ApiResponse> recover(String login, String code, {String? ip}) => post(
    '/auth/recover',
    body: {
      'login': login,
      'recoveryCode': code,
      'newPassword': 'brand-new-pass-1',
      'deviceName': 'Pixel 7',
    },
    ip: ip ?? defaultTestIp,
  );

  Future<int> count(String sql, [List<Object?> parameters = const []]) async {
    final rows = await db.execute(sql, parameters: parameters);
    return rows.first.first! as int;
  }
}
