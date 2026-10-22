import 'dart:math';

import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart' show Result;
import 'package:shared/shared.dart';

import '../db/database.dart';
import 'password_hasher.dart';
import 'tokens.dart';

final _log = Logger('auth');

typedef _Execute = Future<Result> Function(
  String sql, {
  Object? parameters,
  String? what,
  Map<String, Object?>? logParams,
});

const String personalBudgetName = 'Личный бюджет';
const String personalBudgetEmoji = '👛';

enum AuthFailureReason {
  loginTaken('login_taken'),
  badCredentials('bad_credentials'),
  tokenReused('token_reused'),
  sessionRevoked('session_revoked'),
  sessionExpired('session_expired'),
  userDeleted('user_deleted'),
  unknownToken('unknown_token');

  const AuthFailureReason(this.code);

  final String code;
}

class AuthFailure implements Exception {
  AuthFailure(this.reason);

  final AuthFailureReason reason;

  @override
  String toString() => 'AuthFailure: ${reason.code}';
}

class IssuedSession {
  const IssuedSession({
    required this.user,
    required this.sessionId,
    required this.accessToken,
    required this.refreshToken,
  });

  final User user;
  final String sessionId;
  final String accessToken;
  final String refreshToken;
}

class RefreshedTokens {
  const RefreshedTokens({
    required this.userId,
    required this.sessionId,
    required this.accessToken,
    required this.refreshToken,
  });

  final String userId;
  final String sessionId;
  final String accessToken;
  final String refreshToken;
}

class _RefreshOutcome {
  const _RefreshOutcome(
    this.userId,
    this.sessionId, {
    this.failure,
    this.alreadyRevoked = false,
  });

  final String? userId;
  final String? sessionId;
  final AuthFailureReason? failure;
  final bool alreadyRevoked;
}

class Registration {
  const Registration({required this.session, required this.recoveryCode});

  final IssuedSession session;
  final String recoveryCode;
}

class AuthService {
  AuthService({
    required this.db,
    required this.hasher,
    required this.accessTokens,
    Random? random,
  }) : _random = random ?? Random.secure();

  final Database db;
  final PasswordHasher hasher;
  final AccessTokens accessTokens;
  final Random _random;

  Future<Registration> register({
    required String login,
    required String displayName,
    required String password,
    required String deviceName,
  }) async {
    final sw = Stopwatch()..start();
    final normalized = normalizeLogin(login);
    final masked = maskLogin(normalized);
    final taken = await db.execute(
      r'SELECT 1 FROM users WHERE lower(login) = $1',
      parameters: [normalized],
      what: 'login taken check',
      logParams: {'login': masked},
    );
    if (taken.isNotEmpty) {
      _log.info(
        'register rejected reason=${AuthFailureReason.loginTaken.code} '
        'login=$masked in ${sw.elapsedMilliseconds}ms',
      );
      throw AuthFailure(AuthFailureReason.loginTaken);
    }

    final recoveryCode = generateRecoveryCode(_random);
    final passwordHash = await hasher.hash(password, purpose: 'password');
    final recoveryHash = await hasher.hash(
      normalizeRecoveryCode(recoveryCode)!,
      purpose: 'recovery_code',
    );

    final userId = newId();
    final budgetId = newId();
    final sessionId = newId();
    final refreshToken = newRefreshToken(_random);
    final now = DateTime.now().toUtc();
    final categories = buildPresetCategories(
      budgetId: budgetId,
      updatedBy: userId,
      now: now,
      newId: newId,
    );

    final createdAt = await db.transaction('register', (tx) async {
      final inserted = await tx.execute(
        r'INSERT INTO users (id, login, display_name, password_hash, '
        r'recovery_hash) VALUES ($1::uuid, $2, $3, $4, $5) '
        r'ON CONFLICT DO NOTHING RETURNING created_at',
        parameters: [
          userId,
          normalized,
          normalizeText(displayName),
          passwordHash,
          recoveryHash,
        ],
        what: 'insert user',
        logParams: {'userId': userId, 'login': masked},
      );
      if (inserted.isEmpty) return null;
      await tx.execute(
        r'INSERT INTO budgets (id, kind, name, emoji, owner_id, created_at, '
        r"updated_at, updated_by) VALUES ($1::uuid, 'personal', $2, $3, "
        r'$4::uuid, $5, $5, $4::uuid)',
        parameters: [
          budgetId,
          personalBudgetName,
          personalBudgetEmoji,
          userId,
          now,
        ],
        what: 'insert personal budget',
        logParams: {'budgetId': budgetId, 'userId': userId},
      );
      await tx.execute(
        r'INSERT INTO budget_members (budget_id, user_id, role, avatar_color, '
        r"joined_at) VALUES ($1::uuid, $2::uuid, 'owner', $3, $4)",
        parameters: [budgetId, userId, CategoryColor.values.first.name, now],
        what: 'insert budget owner',
        logParams: {'budgetId': budgetId, 'userId': userId},
      );
      for (final category in categories) {
        await tx.execute(
          r'INSERT INTO categories (id, budget_id, name, emoji, color, '
          r'sort_order, is_system, updated_at, updated_by) VALUES ($1::uuid, '
          r'$2::uuid, $3, $4, $5, $6, $7, $8, $9::uuid)',
          parameters: [
            category.id,
            budgetId,
            category.name,
            category.emoji,
            category.color?.name,
            category.sortOrder,
            category.isSystem,
            now,
            userId,
          ],
          what: 'insert preset category',
          logParams: {
            'budgetId': budgetId,
            'categoryId': category.id,
            'sortOrder': category.sortOrder,
          },
        );
      }
      await _insertSession(
        tx.execute,
        sessionId: sessionId,
        userId: userId,
        deviceName: deviceName,
        refreshToken: refreshToken,
      );
      return inserted.first.first! as DateTime;
    });

    if (createdAt == null) {
      _log.info(
        'register rejected reason=${AuthFailureReason.loginTaken.code} '
        'login=$masked (taken concurrently) in ${sw.elapsedMilliseconds}ms',
      );
      throw AuthFailure(AuthFailureReason.loginTaken);
    }

    final user = User(
      id: userId,
      login: normalized,
      displayName: normalizeText(displayName),
      createdAt: createdAt,
    );
    _log.info(
      'register ok userId=$userId sessionId=$sessionId budgetId=$budgetId '
      'categories=${categories.length} in ${sw.elapsedMilliseconds}ms',
    );
    return Registration(
      session: IssuedSession(
        user: user,
        sessionId: sessionId,
        accessToken: accessTokens.issue(userId: userId, sessionId: sessionId),
        refreshToken: refreshToken,
      ),
      recoveryCode: recoveryCode,
    );
  }

  Future<IssuedSession> login({
    required String login,
    required String password,
    required String deviceName,
  }) async {
    final sw = Stopwatch()..start();
    final normalized = normalizeLogin(login);
    final masked = maskLogin(normalized);
    final rows = await db.execute(
      r'SELECT id, login, display_name, password_hash, birthday_month, '
      r'birthday_day, holidays_enabled, holidays_disabled, created_at '
      r'FROM users WHERE lower(login) = $1 AND deleted_at IS NULL',
      parameters: [normalized],
      what: 'find user by login',
      logParams: {'login': masked},
    );
    if (rows.isEmpty) {
      await hasher.verifyDummy(password, purpose: 'password');
      _log.warning(
        'login rejected reason=${AuthFailureReason.badCredentials.code} '
        'login=$masked userFound=false in ${sw.elapsedMilliseconds}ms',
      );
      throw AuthFailure(AuthFailureReason.badCredentials);
    }

    final row = rows.first;
    final userId = row[0]! as String;
    final matches = await hasher.verify(
      password,
      row[3]! as String,
      purpose: 'password',
    );
    if (!matches) {
      _log.warning(
        'login rejected reason=${AuthFailureReason.badCredentials.code} '
        'login=$masked userId=$userId in ${sw.elapsedMilliseconds}ms',
      );
      throw AuthFailure(AuthFailureReason.badCredentials);
    }

    final sessionId = newId();
    final refreshToken = newRefreshToken(_random);
    await _insertSession(
      db.execute,
      sessionId: sessionId,
      userId: userId,
      deviceName: deviceName,
      refreshToken: refreshToken,
    );
    final user = User(
      id: userId,
      login: row[1]! as String,
      displayName: row[2]! as String,
      birthday: MonthDay.fromParts(row[4] as int?, row[5] as int?),
      holidaysEnabled: row[6]! as bool,
      holidaysDisabled: (row[7]! as List<Object?>).cast<String>().toSet(),
      createdAt: row[8]! as DateTime,
    );
    _log.info(
      'login ok userId=$userId sessionId=$sessionId '
      'in ${sw.elapsedMilliseconds}ms',
    );
    return IssuedSession(
      user: user,
      sessionId: sessionId,
      accessToken: accessTokens.issue(userId: userId, sessionId: sessionId),
      refreshToken: refreshToken,
    );
  }

  Future<RefreshedTokens> refresh(String refreshToken) async {
    final sw = Stopwatch()..start();
    final presentedHash = hashRefreshToken(refreshToken);
    final nextToken = newRefreshToken(_random);
    final outcome = await db.transaction('refresh', (tx) async {
      final current = await tx.execute(
        r'SELECT s.id, s.user_id, s.revoked_at IS NOT NULL, '
        r'(s.expires_at <= now()), (u.deleted_at IS NOT NULL) '
        r'FROM sessions s JOIN users u ON u.id = s.user_id '
        r'WHERE s.refresh_hash = $1 FOR UPDATE OF s',
        parameters: [presentedHash],
        what: 'find session by refresh token',
      );
      if (current.isNotEmpty) {
        final row = current.first;
        final sessionId = row[0]! as String;
        final userId = row[1]! as String;
        final failure = row[2] == true
            ? AuthFailureReason.sessionRevoked
            : row[3] == true
            ? AuthFailureReason.sessionExpired
            : row[4] == true
            ? AuthFailureReason.userDeleted
            : null;
        if (failure != null) {
          return _RefreshOutcome(userId, sessionId, failure: failure);
        }
        await tx.execute(
          r'INSERT INTO used_refresh_tokens (refresh_hash, session_id) '
          r'VALUES ($1, $2::uuid)',
          parameters: [presentedHash, sessionId],
          what: 'remember rotated refresh token',
          logParams: {'sessionId': sessionId},
        );
        await tx.execute(
          r'UPDATE sessions SET refresh_hash = $1, last_used_at = now(), '
          r'expires_at = now() + make_interval(days => $2::int) '
          r'WHERE id = $3::uuid',
          parameters: [
            hashRefreshToken(nextToken),
            refreshTokenTtl.inDays,
            sessionId,
          ],
          what: 'rotate refresh token',
          logParams: {
            'sessionId': sessionId,
            'ttlDays': refreshTokenTtl.inDays,
          },
        );
        return _RefreshOutcome(userId, sessionId);
      }

      final used = await tx.execute(
        r'SELECT s.id, s.user_id, s.revoked_at IS NOT NULL '
        r'FROM used_refresh_tokens t JOIN sessions s ON s.id = t.session_id '
        r'WHERE t.refresh_hash = $1 FOR UPDATE OF s',
        parameters: [presentedHash],
        what: 'find session by rotated refresh token',
      );
      if (used.isEmpty) {
        return const _RefreshOutcome(
          null,
          null,
          failure: AuthFailureReason.unknownToken,
        );
      }
      final row = used.first;
      final sessionId = row[0]! as String;
      final userId = row[1]! as String;
      final alreadyRevoked = row[2] == true;
      if (!alreadyRevoked) {
        await tx.execute(
          r'UPDATE sessions SET revoked_at = now() WHERE id = $1::uuid',
          parameters: [sessionId],
          what: 'revoke session after refresh token reuse',
          logParams: {'sessionId': sessionId},
        );
      }
      return _RefreshOutcome(
        userId,
        sessionId,
        failure: AuthFailureReason.tokenReused,
        alreadyRevoked: alreadyRevoked,
      );
    });

    final failure = outcome.failure;
    if (failure != null) {
      final context = [
        'reason=${failure.code}',
        if (outcome.userId != null) 'userId=${outcome.userId}',
        if (outcome.sessionId != null) 'sessionId=${outcome.sessionId}',
        if (failure == AuthFailureReason.tokenReused)
          outcome.alreadyRevoked
              ? '→ session was already revoked'
              : '→ session revoked',
      ].join(' ');
      _log.log(
        failure == AuthFailureReason.tokenReused ? Level.WARNING : Level.INFO,
        'refresh rejected $context in ${sw.elapsedMilliseconds}ms',
      );
      throw AuthFailure(failure);
    }

    final userId = outcome.userId!;
    final sessionId = outcome.sessionId!;
    _log.info(
      'refresh ok userId=$userId sessionId=$sessionId '
      'in ${sw.elapsedMilliseconds}ms',
    );
    return RefreshedTokens(
      userId: userId,
      sessionId: sessionId,
      accessToken: accessTokens.issue(userId: userId, sessionId: sessionId),
      refreshToken: nextToken,
    );
  }

  Future<void> _insertSession(
    _Execute execute, {
    required String sessionId,
    required String userId,
    required String deviceName,
    required String refreshToken,
  }) async {
    await execute(
      r'INSERT INTO sessions (id, user_id, device_name, refresh_hash, '
      r'expires_at) VALUES ($1::uuid, $2::uuid, $3, $4, '
      r'now() + make_interval(days => $5::int))',
      parameters: [
        sessionId,
        userId,
        deviceName,
        hashRefreshToken(refreshToken),
        refreshTokenTtl.inDays,
      ],
      what: 'insert session',
      logParams: {'sessionId': sessionId, 'userId': userId},
    );
  }
}
