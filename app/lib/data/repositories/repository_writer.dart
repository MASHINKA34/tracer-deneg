import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import '../current_user.dart';
import '../db/app_database.dart';
import 'outbox_queue.dart';
import 'repository_errors.dart';

final _log = Logger('repo');

final class EditContext {
  const EditContext({required this.now, required this.userId});

  final DateTime now;
  final String userId;
}

final class RepositoryWriter {
  RepositoryWriter(
    this._db, {
    required this.outbox,
    required this._currentUser,
    required this._now,
  });

  final AppDatabase _db;
  final OutboxQueue outbox;
  final CurrentUser _currentUser;
  final Now _now;

  DateTime now() => normalizeInstant(_now());

  Future<T> edit<T>(
    String entity,
    String op, {
    required String id,
    required Future<T> Function(EditContext c) body,
    String Function(T result)? describe,
  }) async {
    final sw = Stopwatch()..start();
    try {
      final userId = await _currentUser.userId();
      final context = EditContext(now: now(), userId: userId);
      final result = await _db.transaction(() => body(context));
      final details = describe == null ? '' : ' ${describe(result)}';
      _log.fine('$entity $op id=$id$details in ${sw.elapsedMilliseconds}ms');
      await outbox.reportSize('$entity.$op');
      return result;
    } on RepositoryException catch (e) {
      _log.warning(
        '$entity $op rejected id=$id reason=${e.code} '
        'after ${sw.elapsedMilliseconds}ms',
      );
      rethrow;
    } catch (e, st) {
      _log.severe(
        '$entity $op failed id=$id after ${sw.elapsedMilliseconds}ms, '
        'transaction rolled back: ${describeError(e)}',
        e,
        st,
      );
      rethrow;
    }
  }

  Future<T> sync<T>(
    String entity,
    String op, {
    required String target,
    required Future<T> Function() body,
    String Function(T result)? describe,
  }) async {
    final sw = Stopwatch()..start();
    try {
      final result = await _db.transaction(body);
      final details = describe == null ? '' : ' ${describe(result)}';
      _log.fine('$entity $op $target$details in ${sw.elapsedMilliseconds}ms');
      await outbox.reportSize('$entity.$op');
      return result;
    } catch (e, st) {
      _log.severe(
        '$entity $op failed $target after ${sw.elapsedMilliseconds}ms, '
        'transaction rolled back: ${describeError(e)}',
        e,
        st,
      );
      rethrow;
    }
  }

  Stream<T> watch<T>(String entity, String query, Stream<T> stream) =>
      stream.handleError((Object e, StackTrace st) {
        _log.severe('$entity watch failed $query: ${describeError(e)}', e, st);
        Error.throwWithStackTrace(e, st);
      });
}
