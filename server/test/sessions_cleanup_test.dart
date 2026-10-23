import 'package:server/db/database.dart';
import 'package:server/jobs/daily_jobs.dart';
import 'package:server/jobs/sessions_cleanup.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/auth_support.dart';
import 'support/shared_budget_support.dart';
import 'support/test_support.dart';

const _day = Duration(days: 1);

Future<String> _session(
  Database db,
  String userId,
  String label, {
  required DateTime expiresAt,
  DateTime? revokedAt,
  int usedTokens = 0,
}) async {
  final id = newId();
  final createdAt = expiresAt.subtract(_day * 90);
  await db.execute(
    'INSERT INTO sessions (id, user_id, device_name, refresh_hash, '
    r'created_at, last_used_at, expires_at, revoked_at) VALUES ($1::uuid, '
    r'$2::uuid, $3, $4, $5::timestamptz, $5::timestamptz, $6::timestamptz, '
    r'$7::timestamptz)',
    parameters: [
      id,
      userId,
      label,
      'refresh-hash-$label',
      createdAt,
      expiresAt,
      revokedAt,
    ],
  );
  for (var i = 1; i <= usedTokens; i++) {
    await db.execute(
      'INSERT INTO used_refresh_tokens (refresh_hash, session_id, rotated_at) '
      r'VALUES ($1, $2::uuid, $3::timestamptz)',
      parameters: ['used-hash-$label-$i', id, createdAt.add(_day * i)],
    );
  }
  return id;
}

Future<List<String>> _devices(Database db) async {
  final rows = await db.execute(
    'SELECT device_name FROM sessions ORDER BY device_name',
  );
  return [for (final row in rows) row.first! as String];
}

Future<List<String>> _usedTokens(Database db) async {
  final rows = await db.execute(
    'SELECT refresh_hash FROM used_refresh_tokens ORDER BY refresh_hash',
  );
  return [for (final row in rows) row.first! as String];
}

void main() {
  late LogCapture logs;
  late AuthHarness api;

  setUp(() async {
    logs = LogCapture();
    api = await AuthHarness.start();
  });

  test('по подменённым часам удаляются только сессии, отозванные или '
      'истёкшие больше 90 дней назад, вместе с их старыми refresh; живые и '
      'закончившиеся недавно остаются; в логе числа, граница и мс', () async {
    final olga = await registerTestUser(api, 'olga');
    await api.db.execute('DELETE FROM sessions');
    final now = DateTime.utc(2026, 12, 1, 12);
    final cutoff = now.subtract(_day * 90);
    const second = Duration(seconds: 1);
    final db = api.db;
    await _session(
      db,
      olga.id,
      'live',
      expiresAt: now.add(_day * 30),
      usedTokens: 2,
    );
    await _session(db, olga.id, 'live-1s', expiresAt: now.add(second));
    await _session(
      db,
      olga.id,
      'expired-10d',
      expiresAt: now.subtract(_day * 10),
    );
    await _session(db, olga.id, 'expired-90d-edge', expiresAt: cutoff);
    await _session(
      db,
      olga.id,
      'expired-90d-1s',
      expiresAt: cutoff.subtract(second),
      usedTokens: 1,
    );
    await _session(
      db,
      olga.id,
      'revoked-89d',
      expiresAt: now.add(_day),
      revokedAt: now.subtract(_day * 89),
    );
    await _session(
      db,
      olga.id,
      'revoked-90d-edge',
      expiresAt: now.add(_day),
      revokedAt: cutoff,
    );
    await _session(
      db,
      olga.id,
      'revoked-91d',
      expiresAt: now.subtract(_day),
      revokedAt: now.subtract(_day * 91),
      usedTokens: 2,
    );
    await _session(
      db,
      olga.id,
      'revoked-10d-expired-100d',
      expiresAt: now.subtract(_day * 100),
      revokedAt: now.subtract(_day * 10),
    );
    logs.clear();

    final cleanup = SessionsCleanup(db: db, now: () => now);
    final result = await cleanup.run();

    expect(result.revoked, 1);
    expect(result.expired, 2);
    expect(result.deleted, 3);
    expect(result.usedRefreshTokens, 3);
    expect(await _devices(db), [
      'expired-10d',
      'expired-90d-edge',
      'live',
      'live-1s',
      'revoked-89d',
      'revoked-90d-edge',
    ]);
    expect(await _usedTokens(db), ['used-hash-live-1', 'used-hash-live-2']);
    expect(
      logs.text,
      contains(
        RegExp(
          r'INFO  \[jobs\] sessions cleanup deleted=3 revoked=1 expired=2 '
          r'usedRefreshTokens=3 '
          r'revokedOrExpiredBefore=2026-09-02T12:00:00\.000Z retention=90d '
          r'in \d+ms',
        ),
      ),
    );

    logs.clear();
    final again = await cleanup.run();
    expect(again.deleted, 0);
    expect(again.usedRefreshTokens, 0);
    expect(
      logs.text,
      contains('sessions cleanup deleted=0 revoked=0 expired=0 '),
    );
  });

  test('сессия после выхода удаляется через 91 день и остаётся через 89; '
      'живая сессия того же пользователя работает и после уборки', () async {
    final olga = await registerTestUser(api, 'olga');
    final login = await api.login(login: 'olga', deviceName: 'Old phone');
    expect(login.status, 200, reason: login.text);
    final oldRefresh = login.json['refreshToken']! as String;
    final refreshed = await api.post(
      '/auth/refresh',
      body: {'refreshToken': oldRefresh},
    );
    expect(refreshed.status, 200, reason: refreshed.text);
    final oldAccess = refreshed.json['accessToken']! as String;
    final newRefresh = refreshed.json['refreshToken']! as String;
    final logout = await api.post('/auth/logout', bearer: oldAccess);
    expect(logout.status, 204, reason: logout.text);
    final beforeCleanup = await api.post(
      '/auth/refresh',
      body: {'refreshToken': newRefresh},
    );
    expect(beforeCleanup.status, 401);
    expect(await _devices(api.db), ['Old phone', 'Pixel 7']);
    expect(await _usedTokens(api.db), hasLength(1));

    final in89Days = SessionsCleanup(
      db: api.db,
      now: () => DateTime.now().add(_day * 89),
    );
    expect((await in89Days.run()).deleted, 0);
    expect(await _devices(api.db), ['Old phone', 'Pixel 7']);

    final in91Days = SessionsCleanup(
      db: api.db,
      now: () => DateTime.now().add(_day * 91),
    );
    final result = await in91Days.run();
    expect(result.revoked, 1);
    expect(result.expired, 0);
    expect(result.usedRefreshTokens, 1);
    expect(await _devices(api.db), ['Pixel 7']);
    expect(await _usedTokens(api.db), isEmpty);

    final me = await api.send('GET', '/me', bearer: olga.accessToken);
    expect(me.status, 200, reason: me.text);
    final live = await api.post(
      '/auth/refresh',
      body: {'refreshToken': olga.refreshToken},
    );
    expect(live.status, 200, reason: live.text);
    final afterCleanup = await api.post(
      '/auth/refresh',
      body: {'refreshToken': newRefresh},
    );
    expect(afterCleanup.status, beforeCleanup.status);
    expect(afterCleanup.errorCode, beforeCleanup.errorCode);
  });

  test('ошибка базы → warn с границей, error со стеком в jobs, следующая '
      'задача всё равно выполняется', () async {
    final dead = Database.open(
      await deadDatabaseConfig(),
      connectTimeout: const Duration(seconds: 1),
    );
    addTearDown(dead.close);
    final now = DateTime.utc(2026, 12, 1, 12);
    var nextRan = false;
    final jobs = DailyJobs([
      SessionsCleanup(db: dead, now: () => now).job,
      DailyJob('next', () async {
        nextRan = true;
        return 'deleted=0';
      }),
    ]);

    final run = await jobs.runNow('test');

    expect(run.failed, [SessionsCleanup.jobName]);
    expect(run.ok, ['next']);
    expect(nextRan, isTrue);
    expect(
      logs.text,
      contains(
        'WARN  [jobs] sessions cleanup failed '
        'revokedOrExpiredBefore=2026-09-02T12:00:00.000Z retention=90d in ',
      ),
    );
    expect(logs.text, contains('ERROR [jobs] job sessions-cleanup failed in '));
    expect(logs.text, contains('  stack:'));
    expect(logs.text, contains('INFO  [jobs] job next done deleted=0 in'));
  });
}
