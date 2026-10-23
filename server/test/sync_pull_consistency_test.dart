import 'dart:async';

import 'package:postgres/postgres.dart' show Result;
import 'package:server/db/database.dart';
import 'package:server/sync/pull_service.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/auth_support.dart';
import 'support/shared_budget_support.dart';
import 'support/sync_support.dart';
import 'support/test_support.dart';

class _SlowWriter {
  _SlowWriter._(this.done, this._release, this.seq);

  static Future<_SlowWriter> start(
    Database db,
    Future<int> Function(DbSession tx) write,
  ) async {
    final written = Completer<int>();
    final release = Completer<void>();
    final done = db.withConnection(
      'slow writer',
      (connection) => connection.transaction('slow writer tx', (tx) async {
        written.complete(await write(tx));
        await release.future;
      }),
    );
    unawaited(
      done.catchError((Object e) {
        if (!written.isCompleted) written.completeError(e);
      }),
    );
    final seq = await written.future;
    return _SlowWriter._(done, release, seq);
  }

  final Future<void> done;
  final Completer<void> _release;
  final int seq;

  Future<void> commit() {
    _release.complete();
    return done;
  }
}

void main() {
  late LogCapture logs;
  late AuthHarness api;
  late SharedBudgetFixture fixture;
  late TestUser anna;
  late String personal;
  late String category;

  setUp(() async {
    logs = LogCapture();
    api = await AuthHarness.start();
    fixture = SharedBudgetFixture(api);
    anna = await registerTestUser(api, 'anna');
    personal = await fixture.personalBudgetOf(anna.id);
    category =
        (await api.db.execute(
              r'SELECT id FROM categories WHERE budget_id = $1::uuid '
              'AND NOT is_system LIMIT 1',
              parameters: [personal],
            )).first.first!
            as String;
  });

  Future<int> insertExpense(
    Future<Result> Function(String sql, {Object? parameters}) run,
    String id,
  ) async {
    final rows = await run(
      'INSERT INTO expenses (id, budget_id, category_id, amount_kopecks, '
      'spent_on, author_id, created_at, updated_at, updated_by) VALUES '
      r"($1::uuid, $2::uuid, $3::uuid, 500, '2026-10-20', $4::uuid, now(), "
      r'now(), $4::uuid) RETURNING seq',
      parameters: [id, personal, category, anna.id],
    );
    return rows.single.first! as int;
  }

  Future<int> waitingOnGate() async {
    final rows = await api.db.execute(
      'SELECT count(*)::int FROM pg_locks l '
      'JOIN pg_class c ON c.oid = l.relation '
      "WHERE c.relname = 'sync_seq_gate' AND NOT l.granted",
    );
    return rows.single.first! as int;
  }

  test('запись долгой транзакции с меньшим seq не теряется: pull ждёт '
      'её фиксации, а не уводит курсор дальше', () async {
    final start = await pullAs(api, anna);
    final slowId = newId();
    final fastId = newId();

    final slow = await _SlowWriter.start(
      api.db,
      (tx) => insertExpense(tx.execute, slowId),
    );
    final fastSeq = await insertExpense(api.db.execute, fastId);
    expect(slow.seq, lessThan(fastSeq));

    var pullDone = false;
    final firstPull = pullAs(api, anna, cursor: start.cursor);
    unawaited(
      firstPull.then<void>(
        (_) => pullDone = true,
        onError: (Object _) => pullDone = true,
      ),
    );
    final waiting = Stopwatch()..start();
    while (!pullDone && await waitingOnGate() == 0) {
      if (waiting.elapsed > const Duration(seconds: 10)) {
        fail('pull neither finished nor waited for the slow writer');
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    final finishedBeforeCommit = pullDone;
    await slow.commit();

    final first = await firstPull;
    final second = await pullAs(api, anna, cursor: first.cursor);
    final delivered = [
      ...first.expenses.map((e) => e.id),
      ...second.expenses.map((e) => e.id),
    ];
    expect(delivered, containsAll([slowId, fastId]));
    expect(finishedBeforeCommit, isFalse);
    expect(first.expenses.map((e) => e.id), unorderedEquals([slowId, fastId]));
    expect(first.cursor, fastSeq);
    expect(second.totalCount, 0);
  });

  test('транзакция открыта дольше ожидания: pull отдаёт только то, что '
      'ниже последней надёжной границы, и не уводит курсор за её seq', () async {
    final pull = PullService(
      db: api.db,
      barrierTimeout: const Duration(milliseconds: 300),
    );
    final initial = await pull.pull(userId: anna.id, query: SyncPullQuery());
    expect(initial.totalCount, 13);

    final slowId = newId();
    final fastId = newId();
    final slow = await _SlowWriter.start(
      api.db,
      (tx) => insertExpense(tx.execute, slowId),
    );
    await insertExpense(api.db.execute, fastId);
    logs.clear();

    final sw = Stopwatch()..start();
    final blocked = await pull.pull(userId: anna.id, query: SyncPullQuery());
    expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(300));
    expect(blocked.totalCount, 13);
    expect(blocked.cursor, initial.cursor);
    expect(blocked.hasMore, isFalse);
    final fromCursor = await pull.pull(
      userId: anna.id,
      query: SyncPullQuery(cursor: initial.cursor),
    );
    expect(fromCursor.totalCount, 0);
    expect(fromCursor.cursor, initial.cursor);
    expect(
      logs.text,
      contains(
        RegExp(
          r'WARN  \[sync\] pull seq barrier timed out in \d+ms \(limit 300ms\)'
          '.* falling back to last safe bound=${initial.cursor} '
          'userId=${anna.id} cursor=0 limit=500',
        ),
      ),
    );

    await slow.commit();
    final after = await pull.pull(
      userId: anna.id,
      query: SyncPullQuery(cursor: initial.cursor),
    );
    expect(after.expenses.map((e) => e.id), unorderedEquals([slowId, fastId]));
  });

  test('pull не ждёт другой pull: граница берётся под общим замком', () async {
    await api.db.withConnection('other pull', (connection) async {
      await connection.transaction('other pull barrier', (tx) async {
        await tx.execute('LOCK TABLE sync_seq_gate IN SHARE MODE');
        final page = await pullAs(
          api,
          anna,
        ).timeout(const Duration(seconds: 5));
        expect(page.totalCount, 13);
      });
    });
  });

  test('seq выдаётся под замком sync_seq_gate, без кэша значений', () async {
    final sequence = await api.db.execute(
      'SELECT cache_size FROM pg_sequences '
      "WHERE schemaname = 'public' AND sequencename = 'change_seq'",
    );
    expect(sequence.single.single, 1);

    await api.db.withConnection('writer', (connection) async {
      await connection.transaction('writer tx', (tx) async {
        await insertExpense(tx.execute, newId());
        final held = await api.db.execute(
          'SELECT l.mode FROM pg_locks l '
          'JOIN pg_class c ON c.oid = l.relation '
          "WHERE c.relname = 'sync_seq_gate' AND l.granted",
        );
        expect(held.map((row) => row.single), contains('RowExclusiveLock'));
      });
    });
  });
}
