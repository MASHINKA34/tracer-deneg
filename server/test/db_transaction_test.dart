import 'package:postgres/postgres.dart';
import 'package:server/db/database.dart';
import 'package:test/test.dart';

import 'support/test_support.dart';

Future<int> _count(Database db) async {
  final rows = await db.execute('SELECT count(*) FROM items');
  return rows.single.single! as int;
}

void main() {
  late LogCapture logs;
  late Database db;

  setUp(() async {
    logs = LogCapture();
    db = await openScratchDatabase();
    await db.execute('CREATE TABLE items (id integer PRIMARY KEY)');
  });

  group('Database.transaction', () {
    test('успех → всё зафиксировано, результат возвращён, лог с мс', () async {
      final result = await db.transaction('insert two', (tx) async {
        await tx.execute('INSERT INTO items VALUES (1)');
        await tx.execute('INSERT INTO items VALUES (2)');
        return 'ok';
      });
      expect(result, 'ok');
      expect(await _count(db), 2);
      expect(logs.text, contains('DEBUG [db] transaction insert two begin'));
      expect(
        logs.text,
        contains(
          RegExp(r'DEBUG \[db\] transaction insert two committed in \d+ms'),
        ),
      );
    });

    test('исключение в теле → откат и та же ошибка наружу', () async {
      await expectLater(
        db.transaction('insert then fail', (tx) async {
          await tx.execute('INSERT INTO items VALUES (1)');
          throw StateError('boom');
        }),
        throwsA(isA<StateError>()),
      );
      expect(await _count(db), 0);
      expect(
        logs.text,
        contains(
          RegExp(
            r'WARN  \[db\] transaction insert then fail rolled back in \d+ms: StateError: Bad state: boom',
          ),
        ),
      );
    });

    test('ошибка SQL → откат, SQLSTATE в логе', () async {
      await expectLater(
        db.transaction('duplicate', (tx) async {
          await tx.execute('INSERT INTO items VALUES (1)');
          await tx.execute('INSERT INTO items VALUES (1)');
        }),
        throwsA(isA<UniqueViolationException>()),
      );
      expect(await _count(db), 0);
      expect(
        logs.text,
        contains(
          RegExp(
            r'WARN  \[db\] transaction duplicate rolled back in \d+ms: .*sqlState=23505',
          ),
        ),
      );
    });

    test('execute пула работает как раньше', () async {
      await db.execute(
        r'INSERT INTO items VALUES ($1)',
        parameters: [7],
        what: 'insert item',
        logParams: {'id': 7},
      );
      expect(await _count(db), 1);
      expect(logs.text, contains('DEBUG [db] query insert item id=7'));
      expect(
        logs.text,
        contains(
          RegExp(
            r'DEBUG \[db\] query insert item done rows=0 affected=1 in \d+ms',
          ),
        ),
      );
    });
  });

  group('Database.withConnection', () {
    test(
      'одно соединение на всё тело, транзакции на нём, затем закрыто',
      () async {
        late Object pid;
        await db.withConnection('session work', (connection) async {
          pid = (await connection.execute('SELECT pg_backend_pid()'))
              .single
              .single!;
          await connection.execute('CREATE TEMP TABLE scratch (id integer)');
          await connection.transaction('fill scratch', (tx) async {
            await tx.execute('INSERT INTO scratch VALUES (1), (2)');
          });
          final same = await connection.execute(
            'SELECT pg_backend_pid(), (SELECT count(*) FROM scratch)',
          );
          expect(same.single.toList(), [pid, 2]);
        });

        final alive = await db.execute(
          r'SELECT count(*) FROM pg_stat_activity WHERE pid = $1',
          parameters: [pid],
        );
        expect(alive.single.single, 0);
        expect(
          logs.text,
          contains(
            RegExp(
              r'DEBUG \[db\] dedicated connection for session work opened in \d+ms',
            ),
          ),
        );
        expect(
          logs.text,
          contains('DEBUG [db] dedicated connection for session work closed'),
        );
      },
    );

    test('база недоступна → ошибка наружу и warn с адресом', () async {
      final dead = Database.open(await deadDatabaseConfig());
      addTearDown(dead.close);
      await expectLater(
        dead.withConnection('nothing', (_) async {}),
        throwsA(anything),
      );
      expect(
        logs.text,
        contains(
          RegExp(
            r'WARN  \[db\] dedicated connection for nothing to 127\.0\.0\.1:\d+ failed in \d+ms: SocketException',
          ),
        ),
      );
    });
  });
}
