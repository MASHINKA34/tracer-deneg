import 'package:server/budgets/budget_service.dart';
import 'package:server/db/database.dart';
import 'package:server/jobs/daily_jobs.dart';
import 'package:server/jobs/invites_cleanup.dart';
import 'package:test/test.dart';

import 'support/auth_support.dart';
import 'support/budget_support.dart';
import 'support/shared_budget_support.dart';
import 'support/test_support.dart';

Future<void> _invite(
  Database db, {
  required String budgetId,
  required String createdBy,
  required String label,
  required DateTime expiresAt,
  DateTime? revokedAt,
}) => db.execute(
  'INSERT INTO invites (code_hash, budget_id, created_by, created_at, '
  r'expires_at, revoked_at) VALUES ($1, $2::uuid, $3::uuid, $4::timestamptz, '
  r'$5::timestamptz, $6::timestamptz)',
  parameters: [
    label,
    budgetId,
    createdBy,
    expiresAt.subtract(inviteTtl),
    expiresAt,
    revokedAt,
  ],
);

Future<List<String>> _hashes(Database db) async {
  final rows = await db.execute('SELECT code_hash FROM invites ORDER BY 1');
  return [for (final row in rows) row.first! as String];
}

void main() {
  late LogCapture logs;
  late ShiftedClock clock;
  late AuthHarness api;
  late TestUser olga;
  late String familyId;

  setUp(() async {
    logs = LogCapture();
    clock = ShiftedClock();
    api = await AuthHarness.start(now: clock.now);
    olga = await registerTestUser(api, 'olga', displayName: 'Ольга');
    familyId = (await createSharedBudget(api, olga)).id;
    logs.clear();
  });

  test('по подменённым часам удаляются истёкшие (и истекающие ровно сейчас) '
      'и отменённые приглашения, действующие остаются; в логе числа, граница '
      'и мс', () async {
    final now = DateTime.utc(2026, 12, 1, 12);
    const second = Duration(seconds: 1);
    for (final (label, expiresAt, revokedAt) in [
      ('active-1s', now.add(second), null),
      ('active-23h', now.add(const Duration(hours: 23)), null),
      ('expired-now', now, null),
      ('expired-1s', now.subtract(second), null),
      ('expired-30d', now.subtract(const Duration(days: 30)), null),
      (
        'revoked-active',
        now.add(const Duration(hours: 10)),
        now.subtract(const Duration(hours: 1)),
      ),
      (
        'revoked-expired',
        now.subtract(const Duration(days: 2)),
        now.subtract(const Duration(days: 3)),
      ),
    ]) {
      await _invite(
        api.db,
        budgetId: familyId,
        createdBy: olga.id,
        label: label,
        expiresAt: expiresAt,
        revokedAt: revokedAt,
      );
    }

    final cleanup = InvitesCleanup(db: api.db, now: () => now);
    final result = await cleanup.run();

    expect(result.expired, 3);
    expect(result.revoked, 2);
    expect(result.deleted, 5);
    expect(await _hashes(api.db), ['active-1s', 'active-23h']);
    expect(
      logs.text,
      contains(
        RegExp(
          r'INFO  \[jobs\] invites cleanup deleted=5 expired=3 revoked=2 '
          r'expiresAtOrBefore=2026-12-01T12:00:00\.000Z or revoked in \d+ms',
        ),
      ),
    );

    logs.clear();
    expect((await cleanup.run()).deleted, 0);
    expect(
      logs.text,
      contains('invites cleanup deleted=0 expired=0 revoked=0 '),
    );
  });

  test('код через API: прежний после перевыпуска удаляется, новый живёт 24 '
      'часа и по нему входят; после уборки истёкший код даёт ту же ошибку, '
      'что и до неё', () async {
    final boris = await registerTestUser(api, 'boris', displayName: 'Борис');
    final vera = await registerTestUser(api, 'vera', displayName: 'Вера');
    await inviteCodeFor(api, olga, familyId);
    final code = await inviteCodeFor(api, olga, familyId);
    final cleanup = InvitesCleanup(db: api.db, now: clock.now);

    final first = await cleanup.run();
    expect(first.revoked, 1);
    expect(first.expired, 0);
    expect(await _hashes(api.db), hasLength(1));

    clock.offset = const Duration(hours: 23, minutes: 59);
    expect((await cleanup.run()).deleted, 0);
    expect(await _hashes(api.db), hasLength(1));
    final joined = await joinRaw(api, boris, code);
    expect(joined.status, 200, reason: joined.text);

    clock.offset = inviteTtl;
    final beforeCleanup = await joinRaw(api, vera, code);
    expect(beforeCleanup.status, 404, reason: beforeCleanup.text);
    final expired = await cleanup.run();
    expect(expired.expired, 1);
    expect(expired.revoked, 0);
    expect(await _hashes(api.db), isEmpty);
    final afterCleanup = await joinRaw(api, vera, code);
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
      InvitesCleanup(db: dead, now: () => now).job,
      DailyJob('next', () async {
        nextRan = true;
        return 'deleted=0';
      }),
    ]);

    final run = await jobs.runNow('test');

    expect(run.failed, [InvitesCleanup.jobName]);
    expect(run.ok, ['next']);
    expect(nextRan, isTrue);
    expect(
      logs.text,
      contains(
        'WARN  [jobs] invites cleanup failed '
        'expiresAtOrBefore=2026-12-01T12:00:00.000Z or revoked in ',
      ),
    );
    expect(logs.text, contains('ERROR [jobs] job invites-cleanup failed in '));
    expect(logs.text, contains('  stack:'));
    expect(logs.text, contains('INFO  [jobs] job next done deleted=0 in'));
  });
}
