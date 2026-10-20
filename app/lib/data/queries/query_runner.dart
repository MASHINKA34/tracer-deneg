import 'dart:async';

import 'package:drift/drift.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import '../db/app_database.dart';
import '../db/redact_db_error.dart';

final _log = Logger('query');

const Duration slowQueryThreshold = Duration(milliseconds: 100);

String describePeriod(LocalDate? from, LocalDate? to) =>
    from == null && to == null ? 'all' : '${from ?? ''}..${to ?? ''}';

final class QueryRunner {
  QueryRunner(this._db, {required this.slowThreshold});

  final AppDatabase _db;
  final Duration slowThreshold;

  Stream<T> watch<T>(
    String name,
    String params, {
    required Set<ResultSetImplementation<Object?, Object?>> tables,
    required Future<T> Function() run,
    required int Function(T result) rows,
  }) => Stream<T>.multi((controller) {
    var stopped = false;
    var running = false;
    var stale = false;

    Future<void> refresh(String trigger) async {
      if (running) {
        stale = true;
        return;
      }
      running = true;
      var reason = trigger;
      try {
        while (!stopped) {
          stale = false;
          final T result;
          try {
            result = await _timed(name, params, reason, run, rows);
          } catch (e, st) {
            if (stopped) return;
            if (stale) {
              reason = 'change';
              continue;
            }
            controller.addError(e, st);
            return;
          }
          if (stopped) return;
          if (stale) {
            _log.fine(
              'query $name result dropped, tables changed during run '
              '$params',
            );
            reason = 'change';
            continue;
          }
          controller.add(result);
          return;
        }
      } finally {
        running = false;
      }
    }

    final updates = _db
        .tableUpdates(TableUpdateQuery.onAllTables(tables))
        .listen(
          (_) => refresh('change'),
          onDone: () {
            if (stopped) return;
            stopped = true;
            _log.fine('query $name closed with database $params');
            controller.close();
          },
        );
    controller.onCancel = () {
      stopped = true;
      return updates.cancel();
    };
    refresh('listen');
  });

  Future<T> _timed<T>(
    String name,
    String params,
    String trigger,
    Future<T> Function() run,
    int Function(T result) rows,
  ) async {
    final sw = Stopwatch()..start();
    try {
      final result = await run();
      final elapsed = sw.elapsed;
      final count = rows(result);
      if (elapsed > slowThreshold) {
        _log.warning(
          'query $name slow $params rows=$count trigger=$trigger '
          'in ${elapsed.inMilliseconds}ms '
          'threshold=${slowThreshold.inMilliseconds}ms',
        );
      } else {
        _log.fine(
          'query $name $params rows=$count trigger=$trigger '
          'in ${elapsed.inMilliseconds}ms',
        );
      }
      return result;
    } catch (e, st) {
      final error = redactDbError(e);
      _log.severe(
        'query $name failed $params trigger=$trigger '
        'after ${sw.elapsedMilliseconds}ms: ${describeError(error)}',
        error,
        st,
      );
      rethrow;
    }
  }
}
