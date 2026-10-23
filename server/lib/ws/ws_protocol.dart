import 'dart:convert';

const String wsPath = '/api/v1/ws';

const Duration wsClientPingInterval = Duration(seconds: 30);

const Duration wsIdleTimeout = Duration(seconds: 90);

abstract final class WsMessageType {
  static const String changed = 'changed';
  static const String ping = 'ping';
  static const String pong = 'pong';
}

enum WsClose {
  tokenExpired(4401, 'token_expired'),
  idleTimeout(4408, 'idle_timeout'),
  serverShutdown(4503, 'server_shutdown');

  const WsClose(this.code, this.reason);

  final int code;
  final String reason;
}

final String wsPongMessage = jsonEncode({'type': WsMessageType.pong});

String encodeChangedMessage({
  required Iterable<String> budgetIds,
  required int cursor,
}) => jsonEncode({
  'type': WsMessageType.changed,
  'budgetIds': budgetIds.toList()..sort(),
  'cursor': cursor,
});

String? wsMessageType(Object? message) {
  if (message is! String) return null;
  final Object? decoded;
  try {
    decoded = jsonDecode(message);
  } on FormatException {
    return null;
  }
  if (decoded is! Map) return null;
  final type = decoded['type'];
  return type is String ? type : null;
}
