import 'package:server/config/config.dart';
import 'package:server/db/database.dart';
import 'package:server/jobs/daily_job_list.dart';
import 'package:server/jobs/daily_jobs.dart';
import 'package:server/server_app.dart';
import 'package:test/test.dart';

import 'support/maintenance_support.dart';
import 'support/test_support.dart';

void main() {
  late LogCapture logs;

  setUp(() => logs = LogCapture());

  test('в списке ежедневных задач три уборки в постоянном порядке', () async {
    final db = Database.open(await deadDatabaseConfig());
    addTearDown(db.close);

    expect([for (final job in dailyJobList(db)) job.name], dailyJobNames);
  });

  for (final broken in dailyJobNames) {
    test('$broken падает (таблица ${tableOfJob[broken]} недоступна) → error '
        'со стеком, остальные две уборки всё равно выполнены', () async {
      final maintenance = await MaintenanceDatabase.create();
      final now = DateTime.now().toUtc();
      await maintenance.seed(now);
      final table = tableOfJob[broken]!;
      await maintenance.breakTable(table);
      logs.clear();

      final run = await DailyJobs(dailyJobList(maintenance.db, now: () => now))
          .runNow('test');

      await maintenance.repairTable(table);
      expect(run.failed, [broken]);
      expect(run.ok, [...dailyJobNames]..remove(broken));
      final remaining = await maintenance.remaining();
      for (final entry in tableOfJob.entries) {
        expect(
          remaining[entry.value],
          entry.key == broken ? ['fresh', 'old'] : ['fresh'],
          reason: entry.value,
        );
      }
      expect(logs.text, contains('ERROR [jobs] job $broken failed in '));
      expect(
        logs.text,
        contains('42P01: relation "$table" does not exist sqlState=42P01'),
      );
      expect(logs.text, contains('→ continuing with the next job'));
      expect(logs.text, contains('  stack:'));
      for (final healthy in run.ok) {
        expect(
          logs.text,
          contains(RegExp('INFO  \\[jobs\\] job $healthy done deleted=1 ')),
        );
      }
      expect(
        logs.text,
        contains(
          RegExp(
            r'WARN  \[jobs\] daily jobs run #1 finished ok=2 failed=1 '
            '\\($broken\\) in \\d+ms',
          ),
        ),
      );
    });
  }

  test('запущенный сервер при старте убирает отменённые приглашения и '
      'сессии старше 90 дней, живые не трогает', () async {
    final maintenance = await MaintenanceDatabase.create();
    await maintenance.seed(DateTime.now().toUtc());
    logs.clear();

    final server = await startServer(
      ServerConfig.load(
        environment: {
          'HOST': '127.0.0.1',
          'PORT': '0',
          'DATABASE_URL': maintenance.url,
          'JWT_SECRET': 'maintenance-secret-0123456789-abcdefg',
        },
      ),
      dbConnectAttempts: 1,
    );
    addTearDown(() => server.shutdown('test'));

    await waitUntil(() => logs.text.contains('daily jobs run #1 finished'));
    expect(await maintenance.remaining(), {
      'client_errors': ['fresh'],
      'invites': ['fresh'],
      'sessions': ['fresh'],
    });
    expect(
      logs.text,
      contains(
        'INFO  [jobs] job invites-cleanup done deleted=1 expired=0 revoked=1 '
        'in ',
      ),
    );
    expect(
      logs.text,
      contains(
        'INFO  [jobs] job sessions-cleanup done deleted=1 revoked=1 '
        'expired=0 usedRefreshTokens=0 in ',
      ),
    );
    expect(
      logs.text,
      contains(
        RegExp(r'INFO  \[jobs\] daily jobs run #1 finished ok=3 failed=0 in '),
      ),
    );
  });
}
