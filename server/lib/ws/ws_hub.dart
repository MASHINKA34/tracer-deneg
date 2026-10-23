import 'dart:async';

import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart' as pg;
import 'package:shared/logging.dart';

import '../auth/auth_middleware.dart';
import '../db/database.dart';
import '../sync/sync_notifier.dart';
import 'ws_protocol.dart';

final _log = Logger('ws');

const Duration _closeAllTimeout = Duration(seconds: 5);

final class WsPeer {
  const WsPeer({
    required this.messages,
    required this.send,
    required this.close,
    required this.remoteCloseCode,
    required this.remoteCloseReason,
  });

  final Stream<Object?> messages;
  final void Function(String text) send;
  final Future<void> Function(int code, String reason) close;
  final int? Function() remoteCloseCode;
  final String? Function() remoteCloseReason;
}

final class _Connection {
  _Connection(this.id, this.auth, this.peer);

  final String id;
  final AuthContext auth;
  final WsPeer peer;
  final Stopwatch age = Stopwatch()..start();
  final Completer<void> finished = Completer<void>();
  WsClose? closedBy;
  Object? error;
  int received = 0;
  int sent = 0;

  String get userId => auth.userId;

  String get label =>
      'userId=${auth.userId} sessionId=${auth.sessionId} conn=$id';
}

class WsHub implements SyncNotifier {
  WsHub({required this.db, this._now = DateTime.now});

  final Database db;
  final DateTime Function() _now;
  final Map<String, Set<_Connection>> _byUser = {};
  bool _closing = false;

  int get connectionCount =>
      _byUser.values.fold(0, (sum, connections) => sum + connections.length);

  int connectionsOf(String userId) => _byUser[userId]?.length ?? 0;

  void accept(AuthContext auth, WsPeer peer) {
    final connection = _Connection(
      currentRequestId() ?? generateRequestId(),
      auth,
      peer,
    );
    _byUser.putIfAbsent(auth.userId, () => {}).add(connection);
    final expiresIn = auth.expiresAt.difference(_now());
    _log.info(
      'ws connected ${connection.label} '
      'tokenExpiresIn=${expiresIn.inSeconds}s '
      'userConnections=${connectionsOf(auth.userId)} '
      'connections=$connectionCount',
    );
    peer.messages.listen(
      (message) => _onMessage(connection, message),
      onError: (Object e, StackTrace st) => _onError(connection, e, st),
      onDone: () => _onDone(connection),
    );
    if (_closing) {
      _log.info(
        'ws connection arrived during shutdown, closing ${connection.label}',
      );
      _close(connection, WsClose.serverShutdown);
    }
  }

  Future<void> closeAll(String reason) async {
    _closing = true;
    final sw = Stopwatch()..start();
    final all = [for (final connections in _byUser.values) ...connections];
    _log.info(
      'ws closing all connections=${all.length} users=${_byUser.length} '
      '${formatContext({'reason': reason})}',
    );
    for (final connection in all) {
      _close(connection, WsClose.serverShutdown);
    }
    try {
      await Future.wait([
        for (final connection in all) connection.finished.future,
      ]).timeout(_closeAllTimeout);
      _log.info(
        'ws all connections closed count=${all.length} '
        'in ${sw.elapsedMilliseconds}ms',
      );
    } on TimeoutException {
      final open = all.where((c) => !c.finished.isCompleted).length;
      _log.warning(
        'ws close of all connections timed out after '
        '${_closeAllTimeout.inMilliseconds}ms, still open=$open '
        'of ${all.length}, process exit drops them',
      );
    }
  }

  @override
  void budgetsChanged(BudgetsChanged event) {
    unawaited(_broadcast(event));
  }

  Future<void> _broadcast(BudgetsChanged event) async {
    final sw = Stopwatch()..start();
    if (_byUser.isEmpty) {
      _log.fine('ws changed not sent, no connections $event');
      return;
    }
    try {
      final targets = await _recipients(event);
      var delivered = 0;
      var failed = 0;
      for (final MapEntry(key: userId, value: budgetIds) in targets.entries) {
        final message = encodeChangedMessage(
          budgetIds: budgetIds,
          cursor: event.cursor,
        );
        for (final connection in [...?_byUser[userId]]) {
          if (_send(connection, message, WsMessageType.changed)) {
            delivered++;
          } else {
            failed++;
          }
        }
      }
      _log.fine(
        'ws changed broadcast reason=${event.reason} '
        'budgetIds=[${_sorted(event.budgetIds)}] cursor=${event.cursor} '
        'users=${targets.length} recipients=$delivered failed=$failed '
        'in ${sw.elapsedMilliseconds}ms',
      );
    } catch (e, st) {
      _log.warning(
        'ws changed broadcast failed, clients learn on next pull $event '
        'in ${sw.elapsedMilliseconds}ms: ${describeError(e)}',
        e,
        st,
      );
    }
  }

  Future<Map<String, Set<String>>> _recipients(BudgetsChanged event) async {
    final connected = _byUser.keys.toList()..sort();
    final budgetIds = event.budgetIds.toList()..sort();
    final rows = await db.execute(
      'SELECT user_id, budget_id FROM budget_members '
      r'WHERE budget_id = ANY($1::text[]::uuid[]) '
      r'AND user_id = ANY($2::text[]::uuid[]) AND left_at IS NULL',
      parameters: [
        pg.TypedValue(pg.Type.textArray, budgetIds),
        pg.TypedValue(pg.Type.textArray, connected),
      ],
      what: 'connected members of changed budgets',
      logParams: {
        'reason': event.reason,
        'budgets': budgetIds.length,
        'connectedUsers': connected.length,
      },
    );
    final targets = <String, Set<String>>{};
    for (final row in rows) {
      targets.putIfAbsent(row[0]! as String, () => {}).add(row[1]! as String);
    }
    for (final userId in {event.userId, ...event.formerMemberIds}) {
      if (!_byUser.containsKey(userId)) continue;
      targets.putIfAbsent(userId, () => {}).addAll(event.budgetIds);
    }
    return targets;
  }

  bool _send(_Connection connection, String message, String type) {
    if (connection.closedBy != null || connection.finished.isCompleted) {
      return false;
    }
    try {
      connection.peer.send(message);
      connection.sent++;
      return true;
    } catch (e, st) {
      _log.warning(
        'ws send failed type=$type ${connection.label} '
        'size=${message.length}: ${describeError(e)}',
        e,
        st,
      );
      return false;
    }
  }

  void _onMessage(_Connection connection, Object? message) {
    connection.received++;
    _log.warning(
      'ws message ignored ${connection.label} '
      '${_describeMessage(message)}',
    );
  }

  void _onError(_Connection connection, Object error, StackTrace stack) {
    connection.error ??= error;
    _log.warning(
      'ws connection error ${connection.label} '
      'after ${connection.age.elapsedMilliseconds}ms: ${describeError(error)}',
      error,
      stack,
    );
  }

  void _onDone(_Connection connection) {
    if (connection.finished.isCompleted) return;
    _unregister(connection);
    final closedBy = connection.closedBy;
    final reason =
        closedBy?.reason ??
        (connection.error == null ? 'client_closed' : 'connection_error');
    final code = closedBy?.code ?? connection.peer.remoteCloseCode();
    final clientReason = closedBy == null
        ? connection.peer.remoteCloseReason()
        : null;
    final details = formatContext({
      'reason': reason,
      'code': code ?? '-',
      'clientReason': clientReason == null || clientReason.isEmpty
          ? null
          : truncateBody(clientReason, maxBytes: 64),
    });
    _log.info(
      'ws disconnected ${connection.label} $details '
      'duration=${connection.age.elapsedMilliseconds}ms '
      'received=${connection.received} sent=${connection.sent} '
      'connections=$connectionCount',
    );
    connection.finished.complete();
  }

  void _close(_Connection connection, WsClose why) {
    if (connection.closedBy != null || connection.finished.isCompleted) return;
    connection.closedBy = why;
    _unregister(connection);
    _log.info(
      'ws closing by server ${connection.label} '
      'code=${why.code} reason=${why.reason} '
      'after ${connection.age.elapsedMilliseconds}ms',
    );
    unawaited(
      Future<void>.sync(() => connection.peer.close(why.code, why.reason))
          .then<void>(
            (_) {},
            onError: (Object e, StackTrace st) => _log.warning(
              'ws close failed ${connection.label} code=${why.code}: '
              '${describeError(e)}',
              e,
              st,
            ),
          ),
    );
  }

  void _unregister(_Connection connection) {
    final connections = _byUser[connection.userId];
    if (connections == null) return;
    connections.remove(connection);
    if (connections.isEmpty) _byUser.remove(connection.userId);
  }
}

String _sorted(Iterable<String> ids) => (ids.toList()..sort()).join(',');

String _describeMessage(Object? message) {
  if (message is String) {
    final type = wsMessageType(message);
    return formatContext({
      'kind': 'text',
      'type': type == null ? 'none' : truncateBody(type, maxBytes: 32),
      'size': message.length,
    });
  }
  if (message is List<int>) return 'kind=binary size=${message.length}';
  return 'kind=${message.runtimeType}';
}
