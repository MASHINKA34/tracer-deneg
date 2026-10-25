import 'dart:convert';
import 'dart:io';

import 'package:server/auth/auth_service.dart';
import 'package:server/auth/password_hasher.dart';
import 'package:server/auth/tokens.dart';
import 'package:server/config/config.dart';
import 'package:server/db/database.dart';
import 'package:server/db/migrator.dart';
import 'package:server/http/router.dart';
import 'package:server/sync/sync_notifier.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'test_support.dart';

const testJwtSecret = 'test-jwt-secret-0123456789-abcdefghij';

class ApiResponse {
  ApiResponse(this.status, this.headers, this.text);

  final int status;
  final Map<String, String> headers;
  final String text;

  Map<String, Object?> get json => jsonDecode(text) as Map<String, Object?>;

  String? get errorCode =>
      (json['error'] as Map<String, Object?>?)?['code'] as String?;

  @override
  String toString() => 'ApiResponse($status $text)';
}

class AuthHarness {
  AuthHarness._(this.db, this.auth, this.handler);

  static Future<AuthHarness> start({
    AccessTokens? accessTokens,
    SyncNotifier notifier = const NoopSyncNotifier(),
    DateTime Function()? now,
    String? databaseUrl,
  }) async {
    final Database db;
    if (databaseUrl == null) {
      db = await openScratchDatabase();
    } else {
      db = Database.open(DatabaseConfig.parse(databaseUrl));
      addTearDown(() => db.close(reason: 'test done'));
    }
    await Migrator(db, directory: Directory('migrations')).run();
    final auth = AuthService(
      db: db,
      hasher: PasswordHasher(),
      accessTokens: accessTokens ?? AccessTokens(testJwtSecret),
    );
    return AuthHarness._(
      db,
      auth,
      buildHandler(
        db: db,
        auth: auth,
        notifier: notifier,
        now: now ?? DateTime.now,
      ),
    );
  }

  final Database db;
  final AuthService auth;
  final Handler handler;

  Future<ApiResponse> post(
    String path, {
    Object? body,
    String? rawBody,
    String? bearer,
    Map<String, String> headers = const {},
  }) async {
    final response = await handler(
      Request(
        'POST',
        Uri.parse('http://localhost/api/v1$path'),
        body: rawBody ?? (body == null ? '' : jsonEncode(body)),
        headers: {
          'content-type': 'application/json',
          'authorization': ?(bearer == null ? null : 'Bearer $bearer'),
          ...headers,
        },
      ),
    );
    return ApiResponse(
      response.statusCode,
      response.headers,
      await response.readAsString(),
    );
  }

  Future<ApiResponse> send(
    String method,
    String path, {
    Object? body,
    String? rawBody,
    String? bearer,
  }) async {
    final response = await handler(
      Request(
        method,
        Uri.parse('http://localhost/api/v1$path'),
        body: rawBody ?? (body == null ? '' : jsonEncode(body)),
        headers: {
          'content-type': 'application/json',
          'authorization': ?(bearer == null ? null : 'Bearer $bearer'),
        },
      ),
    );
    return ApiResponse(
      response.statusCode,
      response.headers,
      await response.readAsString(),
    );
  }

  Future<ApiResponse> register({
    String login = 'anna',
    String displayName = 'Аня',
    String password = 'secret-pass-1',
    String deviceName = 'Pixel 7',
  }) => post(
    '/auth/register',
    body: {
      'login': login,
      'displayName': displayName,
      'password': password,
      'deviceName': deviceName,
    },
  );

  Future<ApiResponse> login({
    String login = 'anna',
    String password = 'secret-pass-1',
    String deviceName = 'Pixel 7',
  }) => post(
    '/auth/login',
    body: {'login': login, 'password': password, 'deviceName': deviceName},
  );

  Future<int> count(String sql, [List<Object?> parameters = const []]) async {
    final rows = await db.execute(sql, parameters: parameters);
    return rows.first.first! as int;
  }
}
