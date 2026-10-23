import 'dart:io';

import 'package:server/client_errors/client_error_store.dart';
import 'package:server/config/config.dart';
import 'package:server/db/database.dart';
import 'package:server/db/migrator.dart';
import 'package:server/jobs/client_errors_cleanup.dart';
import 'package:server/jobs/daily_jobs.dart';
import 'package:server/server_app.dart';
import 'package:test/test.dart';

import 'support/auth_support.dart';
import 'support/test_support.dart';

Future<String> _insertAt(Database db, DateTime receivedAt, String label) async {
  final rows = await db.execute(
    r'INSERT INTO client_errors (received_at, app_version, kind, message) '
    r"VALUES ($1::timestamptz, '1.0.0+1', 'crash', $2) RETURNING id::text",
    parameters: [receivedAt, label],
  );
  return rows.first.first! as String;
}

Future<List<String>> _messages(Database db) async {
  final rows = await db.execute(
    'SELECT message FROM client_errors ORDER BY received_at',
  );
  return [for (final row in rows) row.first! as String];
}

void main() {
  late LogCapture logs;

  setUp(() => logs = LogCapture());

  group('ClientErrorsCleanup', () {
    late AuthHarness api;

    setUp(() async => api = await AuthHarness.start());

    test('удаляет только отчёты старше 30 дней по подменённым часам, '
        'в логе сколько удалено, граница и мс', () async {
      final now = DateTime.utc(2026, 12, 1, 12);
      const day = Duration(days: 1);
      await _insertAt(api.db, now.subtract(day * 31), 'old-31d');
      await _insertAt(
        api.db,
        now.subtract(day * 30 + const Duration(seconds: 1)),
        'old-30d-1s',
      );
      await _insertAt(api.db, now.subtract(day * 30), 'edge-30d');
      await _insertAt(api.db, now.subtract(day * 29), 'fresh-29d');
      await _insertAt(api.db, now, 'fresh-now');
      logs.clear();

      final cleanup = ClientErrorsCleanup(
        store: ClientErrorStore(api.db),
        now: () => now,
      );
      expect(await cleanup.run(), 2);

      expect(await _messages(api.db), ['edge-30d', 'fresh-29d', 'fresh-now']);
      expect(
        logs.text,
        contains(
          RegExp(
            r'INFO  \[client-errors\] client errors cleanup deleted=2 '
            r'receivedBefore=2026-11-01T12:00:00\.000Z retention=30d '
            r'in \d+ms',
          ),
        ),
      );

      expect(await cleanup.run(), 0);
      expect(logs.text, contains('client errors cleanup deleted=0 '));
    });

    test('отчёт, принятый через POST, удаляется, когда часы ушли на 31 день '
        'вперёд, и остаётся через 29 дней', () async {
      final response = await api.post(
        '/client-errors',
        body: {'kind': 'error', 'appVersion': '1.0.0+1', 'message': 'boom'},
      );
      expect(response.status, 202, reason: response.text);
      final store = ClientErrorStore(api.db);

      final in29Days = ClientErrorsCleanup(
        store: store,
        now: () => DateTime.now().add(const Duration(days: 29)),
      );
      expect(await in29Days.run(), 0);
      expect(await _messages(api.db), ['boom']);

      final in31Days = ClientErrorsCleanup(
        store: store,
        now: () => DateTime.now().add(const Duration(days: 31)),
      );
      expect(await in31Days.run(), 1);
      expect(await _messages(api.db), isEmpty);
    });

    test('ошибка базы → warn с границей в client-errors, error со стеком '
        'в jobs, задача помечена неудачной', () async {
      final dead = Database.open(
        await deadDatabaseConfig(),
        connectTimeout: const Duration(seconds: 1),
      );
      addTearDown(dead.close);
      final now = DateTime.utc(2026, 12, 1, 12);
      final jobs = DailyJobs([
        ClientErrorsCleanup(store: ClientErrorStore(dead), now: () => now).job,
      ]);

      final run = await jobs.runNow('test');

      expect(run.failed, [ClientErrorsCleanup.jobName]);
      expect(
        logs.text,
        contains(
          'WARN  [client-errors] client errors cleanup failed '
          'receivedBefore=2026-11-01T12:00:00.000Z retention=30d in ',
        ),
      );
      expect(
        logs.text,
        contains('ERROR [jobs] job client-errors-cleanup failed in '),
      );
      expect(logs.text, contains('  stack:'));
    });
  });

  test('запущенный сервер убирает старые отчёты при старте: время запуска, '
      'результат и следующий запуск в логе; остановка ждёт задачу', () async {
    final url = await createScratchDatabase();
    final db = Database.open(DatabaseConfig.parse(url));
    addTearDown(() => db.close(reason: 'test done'));
    await Migrator(db, directory: Directory('migrations')).run();
    await _insertAt(
      db,
      DateTime.now().toUtc().subtract(const Duration(days: 45)),
      'old-45d',
    );
    await _insertAt(db, DateTime.now().toUtc(), 'fresh');
    logs.clear();

    final server = await startServer(
      ServerConfig.load(
        environment: {
          'HOST': '127.0.0.1',
          'PORT': '0',
          'DATABASE_URL': url,
          'JWT_SECRET': 'cleanup-secret-0123456789-abcdefghijk',
        },
      ),
      dbConnectAttempts: 1,
    );
    var stopped = false;
    addTearDown(() async {
      if (!stopped) await server.shutdown('test');
    });

    await waitUntil(() => logs.text.contains('daily jobs run #1 finished'));
    expect(await _messages(db), ['fresh']);
    expect(
      logs.text,
      contains(
        'INFO  [jobs] daily jobs scheduled jobs=client-errors-cleanup,'
        'invites-cleanup,sessions-cleanup interval=1d firstRun=now',
      ),
    );
    expect(
      logs.text,
      contains(
        RegExp(
          r'INFO  \[jobs\] daily jobs run #1 started reason=startup '
          r'at=\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}[+-]\d\d:\d\d '
          r'jobs=client-errors-cleanup',
        ),
      ),
    );
    expect(
      logs.text,
      contains(RegExp(r'client errors cleanup deleted=1 receivedBefore=')),
    );
    expect(
      logs.text,
      contains(
        RegExp(r'INFO  \[jobs\] job client-errors-cleanup done deleted=1 in'),
      ),
    );
    expect(
      logs.text,
      contains(
        RegExp(
          r'INFO  \[jobs\] daily jobs run #1 finished ok=3 failed=0 in \d+ms '
          r'nextRun=\d{4}-\d\d-\d\dT',
        ),
      ),
    );

    stopped = true;
    await server.shutdown('test');
    final text = logs.text;
    final order = [
      'closing HTTP server',
      'stopping daily jobs (test) running=false',
      'daily jobs stopped in',
      'closing Postgres pool',
    ].map(text.indexOf).toList();
    expect(order, everyElement(isNonNegative));
    expect(order, orderedEquals([...order]..sort()));
  });
}
