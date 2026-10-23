import 'package:logging/logging.dart';
import 'package:shared/shared.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';

import '../auth/auth_middleware.dart';
import '../http/json.dart';
import 'ws_hub.dart';

final _log = Logger('ws');

Handler wsHandler(WsHub hub) => (Request request) {
  final auth = authContextOf(request);
  if (!_isUpgrade(request)) {
    final headers = formatContext({
      'connection': _header(request, 'connection'),
      'upgrade': _header(request, 'upgrade'),
    });
    _log.info(
      'ws upgrade refused: not a websocket handshake '
      'userId=${auth.userId} sessionId=${auth.sessionId} $headers → 426',
    );
    return errorResponse(
      426,
      ApiErrorCode.badRequest.code,
      'Нужно подключение по WebSocket',
    ).change(headers: {'upgrade': 'websocket'});
  }
  _log.fine(
    'ws upgrade accepted userId=${auth.userId} sessionId=${auth.sessionId}',
  );
  return webSocketHandler(
    (channel, _) => hub.accept(
      auth,
      WsPeer(
        messages: channel.stream,
        send: channel.sink.add,
        close: (code, reason) => channel.sink.close(code, reason),
        remoteCloseCode: () => channel.closeCode,
        remoteCloseReason: () => channel.closeReason,
      ),
    ),
  )(request);
};

bool _isUpgrade(Request request) {
  final connection = request.headers['connection'] ?? '';
  final upgrade = request.headers['upgrade'] ?? '';
  return request.method == 'GET' &&
      connection
          .toLowerCase()
          .split(',')
          .map((token) => token.trim())
          .contains('upgrade') &&
      upgrade.toLowerCase() == 'websocket';
}

String _header(Request request, String name) {
  final value = request.headers[name];
  return value == null ? '-' : truncateBody(value, maxBytes: 64);
}
