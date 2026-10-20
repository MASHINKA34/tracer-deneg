import 'dart:async';

import 'package:drift/drift.dart' show TableUpdate;
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/data/queries/query_runner.dart';

import 'query_fixture.dart';

void main() {
  late QueryHarness h;
  late QueryRunner runner;
  late List<Completer<int>> runs;

  setUp(() {
    h = QueryHarness();
    runner = QueryRunner(h.db, slowThreshold: slowQueryThreshold);
    runs = [];
  });

  tearDown(() => h.dispose());

  Stream<int> watch() => runner.watch(
    'probe',
    'budget=b1',
    tables: {h.db.expenses},
    rows: (_) => 1,
    run: () {
      final run = Completer<int>();
      runs.add(run);
      return run.future;
    },
  );

  void touchExpenses() =>
      h.db.notifyUpdates({TableUpdate.onTable(h.db.expenses)});

  List<String> messages() => [for (final r in h.queryLogs()) r.message];

  test('изменение таблиц во время запуска - старый результат не выходит, '
      'запрос повторяется', () async {
    final probe = Watcher(watch());
    addTearDown(probe.cancel);
    final first = probe.next();
    await pumpEventQueue();
    expect(runs, hasLength(1));

    touchExpenses();
    await pumpEventQueue();
    runs[0].complete(1);
    await pumpEventQueue();
    expect(runs, hasLength(2));
    runs[1].complete(2);

    expect(await first, 2);
    expect(messages(), [
      matches(r'^query probe budget=b1 rows=1 trigger=listen in \d+ms$'),
      'query probe result dropped, tables changed during run budget=b1',
      matches(r'^query probe budget=b1 rows=1 trigger=change in \d+ms$'),
    ]);
  });

  test('чужая таблица не запускает запрос заново', () async {
    final probe = Watcher(watch());
    addTearDown(probe.cancel);
    final first = probe.next();
    await pumpEventQueue();
    runs[0].complete(1);
    expect(await first, 1);

    h.db.notifyUpdates({TableUpdate.onTable(h.db.categories)});
    await pumpEventQueue();

    expect(runs, hasLength(1));
  });

  test('после ошибки поток жив: error в логе, ошибка в потоке, следующее '
      'изменение даёт значение', () async {
    final values = <int>[];
    final errors = <Object>[];
    final sub = watch().listen(values.add, onError: errors.add);
    addTearDown(sub.cancel);
    await pumpEventQueue();

    runs[0].completeError(StateError('disk is gone'));
    await pumpEventQueue();
    touchExpenses();
    await pumpEventQueue();
    runs[1].complete(5);
    await pumpEventQueue();

    expect(errors.single, isA<StateError>());
    expect(values, [5]);
    final severe = h.queryLogs(Level.SEVERE).single;
    expect(
      severe.message,
      matches(
        r'^query probe failed budget=b1 trigger=listen after \d+ms: '
        r'StateError: Bad state: disk is gone$',
      ),
    );
    expect(severe.stackTrace, isNotNull);
  });

  test('после отписки изменения не запускают запрос', () async {
    final probe = Watcher(watch());
    final first = probe.next();
    await pumpEventQueue();
    runs[0].complete(1);
    expect(await first, 1);

    await probe.cancel();
    touchExpenses();
    await pumpEventQueue();

    expect(runs, hasLength(1));
  });

  test('поток закрывается вместе с базой', () async {
    final done = Completer<void>();
    final values = <int>[];
    watch().listen(values.add, onDone: done.complete);
    await pumpEventQueue();
    runs[0].complete(1);
    await pumpEventQueue();

    await h.db.close();
    await done.future.timeout(const Duration(seconds: 5));

    expect(values, [1]);
    expect(messages().last, 'query probe closed with database budget=b1');
  });
}
