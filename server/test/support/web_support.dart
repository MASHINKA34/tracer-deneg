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
import 'package:server/web/web_page.dart';
import 'package:shelf/shelf.dart';

import 'auth_support.dart';
import 'limits_support.dart';
import 'test_support.dart';

const formContentType = 'application/x-www-form-urlencoded';

class WebPage {
  WebPage(this.status, this.headers, this.html);

  final int status;
  final Map<String, String> headers;
  final String html;

  String? get contentType => headers['content-type'];

  String get text => html
      .replaceAll(RegExp(r'<style>.*?</style>', dotAll: true), ' ')
      .replaceAll(RegExp(r'<[^>]+>'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  @override
  String toString() => 'WebPage($status $text)';
}

class WebHarness {
  WebHarness._(this.db, this.limits, this.clock, this.handler);

  static Future<WebHarness> start({
    PrivacySettings privacy = const PrivacySettings(),
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
    return WebHarness._(
      db,
      limits,
      clock,
      buildHandler(
        db: db,
        auth: auth,
        inviteCodeSecret: testInviteCodeSecret,
        limits: limits,
        privacy: privacy,
      ),
    );
  }

  final Database db;
  final RequestLimits limits;
  final FakeClock clock;
  final Handler handler;

  Future<WebPage> get(String path, {String ip = defaultTestIp}) async {
    final response = await handler(
      Request(
        'GET',
        Uri.parse('http://localhost$path'),
        context: {'shelf.io.connection_info': FakeConnectionInfo(ip)},
      ),
    );
    return WebPage(
      response.statusCode,
      response.headers,
      await response.readAsString(),
    );
  }

  Future<WebPage> postForm(
    String path, {
    Map<String, String>? fields,
    Object? rawBody,
    String contentType = formContentType,
    String ip = defaultTestIp,
    String? forwardedFor,
  }) async {
    final response = await handler(
      Request(
        'POST',
        Uri.parse('http://localhost$path'),
        body:
            rawBody ??
            fields!.entries
                .map(
                  (e) =>
                      '${Uri.encodeQueryComponent(e.key)}='
                      '${Uri.encodeQueryComponent(e.value)}',
                )
                .join('&'),
        headers: {
          'content-type': contentType,
          'x-forwarded-for': ?forwardedFor,
        },
        context: {'shelf.io.connection_info': FakeConnectionInfo(ip)},
      ),
    );
    return WebPage(
      response.statusCode,
      response.headers,
      await response.readAsString(),
    );
  }

  Future<WebPage> deleteByForm(
    String login,
    String password, {
    String ip = defaultTestIp,
  }) => postForm(
    deleteAccountPath,
    fields: {'login': login, 'password': password},
    ip: ip,
  );

  Future<ApiResponse> api(
    String method,
    String path, {
    Object? body,
    String? bearer,
    String ip = '198.51.100.250',
  }) async {
    final response = await handler(
      Request(
        method,
        Uri.parse('http://localhost/api/v1$path'),
        body: body == null ? '' : jsonEncode(body),
        headers: {
          'content-type': 'application/json',
          'authorization': ?(bearer == null ? null : 'Bearer $bearer'),
        },
        context: {'shelf.io.connection_info': FakeConnectionInfo(ip)},
      ),
    );
    return ApiResponse(
      response.statusCode,
      response.headers,
      await response.readAsString(),
    );
  }

  Future<ApiResponse> register(String login, String password) => api(
    'POST',
    '/auth/register',
    body: {
      'login': login,
      'displayName': 'Тест',
      'password': password,
      'deviceName': 'Pixel 7',
    },
  );

  Future<ApiResponse> login(
    String login,
    String password, {
    String ip = defaultTestIp,
  }) => api(
    'POST',
    '/auth/login',
    body: {'login': login, 'password': password, 'deviceName': 'Pixel 7'},
    ip: ip,
  );

  Future<int> count(String sql, [List<Object?> parameters = const []]) async {
    final rows = await db.execute(sql, parameters: parameters);
    return rows.first.first! as int;
  }
}
