import 'dart:convert';
import 'dart:io';

import 'package:server/admin/admin_cli.dart';
import 'package:server/admin/errors_table.dart';
import 'package:server/client_errors/client_error_fields.dart';
import 'package:server/client_errors/client_error_store.dart';
import 'package:server/config/config.dart';
import 'package:server/db/database.dart';
import 'package:server/db/migrator.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/test_support.dart';

const _uuid = r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}';

void main() {
  group('parseAge / parseErrorsArgs', () {
    test('возраст: минуты, часы, дни', () {
      expect(parseAge('30m'), const Duration(minutes: 30));
      expect(parseAge('12h'), const Duration(hours: 12));
      expect(parseAge('1d'), const Duration(days: 1));
      expect(parseAge(' 7D '), const Duration(days: 7));
    });

    test('неверный возраст → AdminUsageException с понятным текстом', () {
      for (final bad in ['', 'abc', '0d', '1w', '-1d', '1.5h', 'd1']) {
        expect(
          () => parseAge(bad),
          throwsA(
            isA<AdminUsageException>().having(
              (e) => e.message,
              'message',
              contains('--since'),
            ),
          ),
          reason: bad,
        );
      }
    });

    test('--since обязателен, --limit по умолчанию 50, оба вида записи', () {
      final plain = parseErrorsArgs(['--since', '1d']);
      expect(plain.since, const Duration(days: 1));
      expect(plain.limit, errorsDefaultLimit);
      expect(plain.sinceText, '1d');

      final joined = parseErrorsArgs(['--limit=5', '--since=2h']);
      expect(joined.since, const Duration(hours: 2));
      expect(joined.limit, 5);

      for (final args in [
        <String>[],
        ['--limit', '5'],
        ['--since'],
        ['--since', '1d', '--limit', '0'],
        ['--since', '1d', '--limit', '1001'],
        ['--since', '1d', '--limit', 'ten'],
        ['--since', '1d', '--full'],
      ]) {
        expect(
          () => parseErrorsArgs(args),
          throwsA(isA<AdminUsageException>()),
          reason: '$args',
        );
      }
    });
  });

  group('formatErrorsTable', () {
    ClientErrorRow row({String message = 'StateError: boom'}) => ClientErrorRow(
      id: '3f0c2a52-6a3b-4c1e-9d0f-0123456789ab',
      receivedAt: DateTime.utc(2026, 10, 23, 8, 40, 12),
      userId: null,
      appVersion: '1.0.0+1',
      androidSdk: 36,
      deviceModel: 'Pixel 7',
      kind: 'crash',
      message: message,
      stackBytes: 1536,
      logsBytes: null,
    );

    test('пусто → одна строка «none»', () {
      final lines = formatErrorsTable(
        const ClientErrorPage(rows: [], total: 0),
        since: DateTime.utc(2026, 10, 22, 8, 40, 12),
        sinceText: '1d',
      );
      expect(lines, hasLength(1));
      expect(lines.single, startsWith('client errors since 2026-10-'));
      expect(lines.single, endsWith('(1d): none'));
    });

    test('колонки выровнены, размеры читаемые, управляющие символы и '
        'переводы строк из отчёта не попадают в терминал', () {
      final lines = formatErrorsTable(
        ClientErrorPage(
          rows: [
            row(),
            row(
              message:
                  'Boom${String.fromCharCode(0x1B)}[2J\nnext'
                  '${String.fromCharCode(0x202E)}line ${'x' * 200}',
            ),
          ],
          total: 5,
        ),
        since: DateTime.utc(2026, 10, 22, 8, 40, 12),
        sinceText: '1d',
      );

      expect(lines[0], endsWith('(1d): 5 found, showing 2, newest first'));
      expect(
        lines[1],
        matches(
          RegExp(
            r'^received +id +kind +app +sdk +device +user +stack +logs +'
            r'message$',
          ),
        ),
      );
      expect(lines[2], matches(RegExp(r'^-+( +-+){9}$')));
      expect(
        lines[3],
        matches(
          RegExp(
            r'^2026-10-23 \d\d:40:12 +3f0c2a52-6a3b-4c1e-9d0f-0123456789ab +'
            r'crash +1\.0\.0\+1 +36 +Pixel 7 +- +1\.5 KB +- +StateError: boom$',
          ),
        ),
      );
      expect(lines[4], contains('Boom [2J next line xxx'));
      expect(lines[4], endsWith('…'));
      for (final line in lines) {
        expect(line.runes.where((r) => r < 0x20 || r == 0x202E), isEmpty);
      }
      expect(lines[3].indexOf('crash'), lines[1].indexOf('kind'));
      expect(lines[4].indexOf('crash'), lines[1].indexOf('kind'));
      expect(lines.last, '… 3 more not shown, raise --limit to see them');
    });

    test('formatSize', () {
      expect(formatSize(null), '-');
      expect(formatSize(512), '512 B');
      expect(formatSize(204800), '200.0 KB');
      expect(formatSize(3 * 1024 * 1024), '3.0 MB');
    });
  });

  group('runAdmin errors против Postgres', () {
    late LogCapture logs;
    late List<String> out;

    setUp(() {
      logs = LogCapture();
      out = [];
    });

    Future<String> migratedDatabase() async {
      final url = await createScratchDatabase();
      final db = Database.open(DatabaseConfig.parse(url));
      addTearDown(() => db.close(reason: 'test done'));
      await Migrator(db, directory: Directory('migrations')).run();
      final store = ClientErrorStore(db);
      for (final (kind, message, logsText) in [
        (ClientErrorKind.crash, 'StateError: first', 'l' * 3000),
        (ClientErrorKind.userReport, 'Отчёт пользователя', null),
      ]) {
        await store.insert(
          prepareClientError(
            ClientErrorReport(
              appVersion: '1.0.0+1',
              androidSdk: 36,
              deviceModel: 'Pixel 7',
              kind: kind,
              message: message,
              stack: '#0 main',
              logs: logsText,
            ),
          ),
        );
      }
      await db.execute(
        "INSERT INTO client_errors (received_at, app_version, kind, message) "
        "VALUES (now() - interval '2 days', '0.9.0+1', 'error', 'too old')",
      );
      logs.clear();
      return url;
    }

    test('печатает таблицу отчётов за период, старые не показывает', () async {
      final url = await migratedDatabase();

      final code = await runAdmin(
        ['errors', '--since', '1d'],
        environment: {'DATABASE_URL': url},
        out: out.add,
      );

      expect(code, adminExitOk, reason: logs.text);
      expect(out[0], contains('(1d): 2 found, showing 2, newest first'));
      expect(out[1], startsWith('received'));
      expect(out, hasLength(5));
      expect(out[3], matches(RegExp('  $_uuid  user_report  1\\.0\\.0\\+1 ')));
      expect(out[3], endsWith('Отчёт пользователя'));
      expect(out[4], contains('crash'));
      expect(out[4], contains('2.9 KB'));
      expect(out[4], endsWith('StateError: first'));
      expect(out.join('\n'), isNot(contains('too old')));
      expect(
        logs.text,
        contains(
          RegExp(
            r'INFO  \[admin\] admin errors since=1d \(\d{4}-\d\d-\d\dT[^)]+\) '
            r'limit=50 db=postgres://milionchik:\*\*\*@',
          ),
        ),
      );
      expect(
        logs.text,
        contains(RegExp(r'admin errors done found=2 shown=2 in \d+ms')),
      );
    });

    test('--limit 1 и --since 3d: один отчёт и подсказка о скрытых', () async {
      final url = await migratedDatabase();

      final code = await runAdmin(
        ['errors', '--since', '3d', '--limit', '1'],
        environment: {'DATABASE_URL': url},
        out: out.add,
      );

      expect(code, adminExitOk, reason: logs.text);
      expect(out[0], contains('(3d): 3 found, showing 1, newest first'));
      expect(out.last, '… 2 more not shown, raise --limit to see them');
    });

    test('DATABASE_URL из .env, переменная окружения важнее', () async {
      final url = await migratedDatabase();
      final dir = await Directory.systemTemp.createTemp('admin_env_');
      addTearDown(() => dir.delete(recursive: true));
      final envFile = File('${dir.path}/.env')
        ..writeAsStringSync('DATABASE_URL=$url\nLOG_LEVEL=debug\n');

      expect(
        await runAdmin(
          ['errors', '--since', '1d'],
          environment: const {},
          envFile: envFile,
          out: out.add,
        ),
        adminExitOk,
      );
      expect(out[0], contains('2 found'));

      final dead = await deadDatabaseConfig();
      out.clear();
      expect(
        await runAdmin(
          ['errors', '--since', '1d'],
          environment: {
            'DATABASE_URL':
                'postgres://milionchik:milionchik@127.0.0.1:${dead.port}/x',
          },
          envFile: envFile,
          out: out.add,
        ),
        adminExitFailure,
      );
      expect(out, isEmpty);
    });

    test('база недоступна → код 1 и понятная строка ошибки без пароля', () async {
      final dead = await deadDatabaseConfig();

      final code = await runAdmin(
        ['errors', '--since', '1d'],
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
      expect(logs.text, contains('→ is the database running?'));
      expect(logs.text, isNot(contains('topsecret-db-pass')));
    });

    test(
      'нет DATABASE_URL, неверный URL, нет таблицы → код 1 и причина',
      () async {
        expect(
          await runAdmin(
            ['errors', '--since', '1d'],
            environment: const {},
            out: out.add,
          ),
          adminExitFailure,
        );
        expect(logs.text, contains('ERROR [admin] DATABASE_URL is not set'));

        expect(
          await runAdmin(
            ['errors', '--since', '1d'],
            environment: const {'DATABASE_URL': 'mysql://x@y/z'},
            out: out.add,
          ),
          adminExitFailure,
        );
        expect(logs.text, contains('ERROR [admin] DATABASE_URL is invalid:'));

        final empty = await createScratchDatabase();
        expect(
          await runAdmin(
            ['errors', '--since', '1d'],
            environment: {'DATABASE_URL': empty},
            out: out.add,
          ),
          adminExitFailure,
        );
        expect(
          logs.text,
          contains(
            'ERROR [admin] table client_errors does not exist in db=scratch_',
          ),
        );
        expect(out, isEmpty);
      },
    );

    test(
      'без аргументов и с неизвестной командой → 64 и справка; help → 0',
      () async {
        expect(
          await runAdmin(const [], environment: const {}, out: out.add),
          adminExitUsage,
        );
        expect(out.single, adminUsage);
        out.clear();
        expect(
          await runAdmin(const ['purge'], environment: const {}, out: out.add),
          adminExitUsage,
        );
        expect(logs.text, contains('ERROR [admin] unknown command "purge"'));
        out.clear();
        expect(
          await runAdmin(
            const ['errors', '--since', 'week'],
            environment: const {},
            out: out.add,
          ),
          adminExitUsage,
        );
        expect(
          logs.text,
          contains(
            'ERROR [admin] errors: --since must look like 30m, 12h or 1d',
          ),
        );
        out.clear();
        expect(
          await runAdmin(const ['help'], environment: const {}, out: out.add),
          adminExitOk,
        );
        expect(out.single, contains('errors --since <age> [--limit <N>]'));
      },
    );
  });

  test(
    'dart run bin/admin.dart errors: таблица в stdout, логи в stderr',
    () async {
      LogCapture();
      final url = await createScratchDatabase();
      final db = Database.open(DatabaseConfig.parse(url));
      addTearDown(() => db.close(reason: 'test done'));
      await Migrator(db, directory: Directory('migrations')).run();
      await ClientErrorStore(db).insert(
        prepareClientError(
          const ClientErrorReport(
            appVersion: '1.0.0+7',
            androidSdk: 30,
            deviceModel: 'sdk_gphone64',
            kind: ClientErrorKind.error,
            message: 'FlutterError: overflow',
          ),
        ),
      );

      final result = await Process.run(
        Platform.resolvedExecutable,
        ['run', 'bin/admin.dart', 'errors', '--since', '1d'],
        environment: {'DATABASE_URL': url, 'LOG_LEVEL': 'info'},
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );

      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      final stdoutText = result.stdout as String;
      final stderrText = result.stderr as String;
      expect(stdoutText, contains('1 found, showing 1, newest first'));
      expect(stdoutText, contains('FlutterError: overflow'));
      expect(stdoutText, isNot(contains('[admin]')));
      expect(stderrText, contains('INFO  [admin] admin errors done found=1'));
      expect(stderrText, isNot(contains('FlutterError: overflow')));
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
