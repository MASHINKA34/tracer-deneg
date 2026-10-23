import 'dart:convert';
import 'dart:io';

import 'package:server/admin/admin_cli.dart';
import 'package:test/test.dart';

import 'support/maintenance_support.dart';
import 'support/test_support.dart';

void main() {
  late LogCapture logs;
  late List<String> out;

  setUp(() {
    logs = LogCapture();
    out = [];
  });

  test('jobs: один запуск всех уборок по подменённым часам, результат каждой '
      'в stdout, код 0', () async {
    final maintenance = await MaintenanceDatabase.create();
    final now = DateTime.utc(2026, 12, 1, 12);
    await maintenance.seed(now);
    logs.clear();

    final code = await runAdmin(
      ['jobs'],
      environment: {'DATABASE_URL': maintenance.url},
      out: out.add,
      now: () => now,
    );

    expect(code, adminExitOk, reason: logs.text);
    expect(out, [
      'client-errors-cleanup: ok deleted=1',
      'invites-cleanup: ok deleted=1 expired=0 revoked=1',
      'sessions-cleanup: ok deleted=1 revoked=1 expired=0 usedRefreshTokens=0',
    ]);
    expect(await maintenance.remaining(), {
      'client_errors': ['fresh'],
      'invites': ['fresh'],
      'sessions': ['fresh'],
    });
    expect(
      logs.text,
      contains(
        'INFO  [admin] admin jobs: running daily jobs once now '
        'db=postgres://milionchik:***@',
      ),
    );
    expect(
      logs.text,
      contains(
        'INFO  [jobs] daily jobs run #1 started reason=admin '
        'at=2026-12-01T',
      ),
    );
    expect(
      logs.text,
      contains(
        RegExp(
          r'INFO  \[admin\] admin jobs done ok=3 failed=0 in \d+ms → exit 0',
        ),
      ),
    );
    expect(logs.text, isNot(contains('milionchik:milionchik@')));
  });

  test('jobs: упала одна задача → остальные выполнены, в stdout FAILED, '
      'error со стеком в логе, код 1', () async {
    final maintenance = await MaintenanceDatabase.create();
    final now = DateTime.utc(2026, 12, 1, 12);
    await maintenance.seed(now);
    await maintenance.breakTable('invites');
    logs.clear();

    final code = await runAdmin(
      ['jobs'],
      environment: {'DATABASE_URL': maintenance.url},
      out: out.add,
      now: () => now,
    );

    await maintenance.repairTable('invites');
    expect(code, adminExitFailure);
    expect(out, [
      'client-errors-cleanup: ok deleted=1',
      'invites-cleanup: FAILED, see the error in the log',
      'sessions-cleanup: ok deleted=1 revoked=1 expired=0 usedRefreshTokens=0',
    ]);
    expect(await maintenance.remaining(), {
      'client_errors': ['fresh'],
      'invites': ['fresh', 'old'],
      'sessions': ['fresh'],
    });
    expect(logs.text, contains('ERROR [jobs] job invites-cleanup failed in '));
    expect(logs.text, contains('  stack:'));
    expect(
      logs.text,
      contains(
        RegExp(
          r'ERROR \[admin\] admin jobs done ok=2 failed=1 \(invites-cleanup\) '
          r'in \d+ms → exit 1',
        ),
      ),
    );
  });

  test('jobs с лишним аргументом → 64 и справка; база недоступна → 1 и '
      'понятная строка без пароля', () async {
    expect(
      await runAdmin(
        const ['jobs', '--force'],
        environment: const {},
        out: out.add,
      ),
      adminExitUsage,
    );
    expect(out.single, adminUsage);
    expect(adminUsage, contains('\n  jobs\n'));
    expect(
      logs.text,
      contains('ERROR [admin] jobs: jobs takes no options, got "--force"'),
    );

    final dead = await deadDatabaseConfig();
    out.clear();
    final code = await runAdmin(
      ['jobs'],
      environment: {
        'DATABASE_URL':
            'postgres://milionchik:topsecret-db-pass@127.0.0.1:${dead.port}/nothing',
      },
      out: out.add,
    );

    expect(code, adminExitFailure);
    expect(out, isEmpty);
    expect(
      logs.text,
      contains(
        'ERROR [admin] cannot connect to Postgres 127.0.0.1:${dead.port} '
        'db=nothing: SocketException',
      ),
    );
    expect(logs.text, isNot(contains('topsecret-db-pass')));
  });

  test(
    'dart run bin/admin.dart jobs: результаты в stdout, логи задач в stderr',
    () async {
      final maintenance = await MaintenanceDatabase.create();
      await maintenance.seed(DateTime.now().toUtc());

      final result = await Process.run(
        Platform.resolvedExecutable,
        ['run', 'bin/admin.dart', 'jobs'],
        environment: {'DATABASE_URL': maintenance.url, 'LOG_LEVEL': 'info'},
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );

      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      final stdoutText = result.stdout as String;
      final stderrText = result.stderr as String;
      expect(stdoutText, contains('invites-cleanup: ok deleted=1 '));
      expect(stdoutText, contains('sessions-cleanup: ok deleted=1 '));
      expect(stdoutText, isNot(contains('[jobs]')));
      expect(stderrText, contains('INFO  [jobs] job invites-cleanup done'));
      expect(stderrText, contains('INFO  [jobs] job sessions-cleanup done'));
      expect(stderrText, contains('INFO  [admin] admin jobs done ok=3'));
      expect(await maintenance.remaining(), {
        'client_errors': ['fresh'],
        'invites': ['fresh'],
        'sessions': ['fresh'],
      });
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
