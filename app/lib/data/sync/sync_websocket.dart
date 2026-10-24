import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:math' as math;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../core/network_status.dart';
import '../api/api_config.dart';
import '../api/api_exception.dart';
import '../api/api_providers.dart';
import '../api/token_store.dart';
import 'sync_engine.dart';
import 'sync_triggers.dart';

final _log = Logger('ws');

const String syncWebSocketPath = '/ws';

const Duration wsPingInterval = Duration(seconds: 30);

const Duration wsConnectTimeout = Duration(seconds: 10);

const Duration wsStableAfter = Duration(seconds: 30);

abstract final class WsCloseCode {
  static const int normal = 1000;
  static const int noPong = 4000;
  static const int tokenExpired = 4401;
  static const int idleTimeout = 4408;
  static const int serverShutdown = 4503;
}

abstract final class WsCloseReason {
  static const String background = 'app_in_background';
  static const String signedOut = 'signed_out';
  static const String stopped = 'app_stopped';
  static const String noPong = 'no_pong';
  static const String notNeeded = 'not_needed';
}

final String _pingMessage = jsonEncode({'type': 'ping'});

typedef WebSocketConnect = Future<WebSocketChannel> Function(
  Uri url,
  Map<String, String> headers,
);

typedef WebSocketTimer = Timer Function(
  Duration delay,
  void Function() callback,
);

typedef RejectedTokenRefresh = Future<void> Function(String accessToken);

typedef ChangedSync = Future<SyncCycleResult> Function();

typedef MonotonicClock = Duration Function();

enum WsPhase { off, connecting, open, refreshing, waiting }

Future<WebSocketChannel> connectWebSocket(
  Uri url,
  Map<String, String> headers,
) async {
  final channel = IOWebSocketChannel.connect(
    url,
    headers: headers,
    connectTimeout: wsConnectTimeout,
  );
  await channel.ready;
  return channel;
}

Uri webSocketUrl(ApiConfig config) {
  final base = config.baseUrl;
  return base.replace(
    scheme: base.isScheme('https') ? 'wss' : 'ws',
    path: '${base.path}$syncWebSocketPath',
  );
}

int? webSocketHandshakeStatus(Object? error) => switch (error) {
  WebSocketChannelException(:final inner) => webSocketHandshakeStatus(inner),
  io.WebSocketException(:final httpStatusCode) => httpStatusCode,
  _ => null,
};

final class SyncWebSocket {
  SyncWebSocket({
    required this._url,
    required this._readTokens,
    required this._refresh,
    required this._changed,
    WebSocketConnect? connect,
    WebSocketTimer? timer,
    math.Random? random,
    MonotonicClock? clock,
  }) : _connect = connect ?? connectWebSocket,
       _timer = timer ?? Timer.new,
       _random = random ?? math.Random(),
       _clock = clock ?? _stopwatchClock();

  final Uri Function() _url;
  final Future<AuthTokens?> Function() _readTokens;
  final RejectedTokenRefresh _refresh;
  final ChangedSync _changed;
  final WebSocketConnect _connect;
  final WebSocketTimer _timer;
  final math.Random _random;
  final MonotonicClock _clock;

  bool _started = false;
  bool _disposed = false;
  bool _signedIn = false;
  bool _foreground = true;
  bool? _online;
  WsPhase _phase = WsPhase.off;
  int _run = 0;
  int _failures = 0;
  bool _dropped = false;
  bool _refreshedLast = false;
  WebSocketChannel? _channel;
  StreamSubscription<Object?>? _messages;
  Duration? _openedAt;
  String? _accessToken;
  Timer? _ping;
  Duration? _pingSentAt;
  Timer? _reconnect;
  Duration? _reconnectDelay;
  Duration? _reconnectFrom;

  WsPhase get phase => _phase;

  int get failures => _failures;

  bool get reconnectScheduled => _reconnect != null;

  Duration? get reconnectDelay => _reconnect == null ? null : _reconnectDelay;

  bool get _wanted => _started && !_disposed && _signedIn && _foreground;

  void start({required bool signedIn, required bool foreground}) {
    if (_disposed) return;
    _started = true;
    _signedIn = signedIn;
    _foreground = foreground;
    _log.info(
      'ws realtime on: connect while the app is on screen, ping every '
      '${wsPingInterval.inSeconds}s, reconnect pause '
      '${syncRetryFirst.inSeconds}s→${syncRetryMax.inSeconds}s; '
      'session=${signedIn ? 'active' : 'none'} foreground=$foreground',
    );
    _begin('app started');
  }

  void stop(String why) {
    if (!_started) return;
    _started = false;
    _end(why, WsCloseReason.stopped);
  }

  void dispose() {
    if (_disposed) return;
    stop('disposed');
    _disposed = true;
  }

  void sessionChanged({required bool active, required String change}) {
    if (_disposed) return;
    final was = _signedIn;
    _signedIn = active;
    if (!_started) return;
    if (was == active) {
      _log.fine('ws: session $change, still active=$active');
      return;
    }
    if (!active) {
      _end('session $change', WsCloseReason.signedOut);
      return;
    }
    _begin('signed in (session $change)');
  }

  void resumed() {
    if (_disposed || !_started || _foreground) return;
    _foreground = true;
    _begin('app back from background');
  }

  void paused() {
    if (_disposed || !_started || !_foreground) return;
    _foreground = false;
    _end('app in background', WsCloseReason.background);
  }

  void networkChanged(List<ConnectivityResult> results) {
    if (_disposed || !_started) return;
    final online = isOnline(results);
    final was = _online;
    _online = online;
    final types = results.map((r) => r.name).join(',');
    if (was == null || online == was || !online) {
      _log.fine(
        'ws: network online=$online types=$types '
        '${was == null ? '(first event)' : '(was $was)'} → nothing to do, '
        'phase=${_phase.name}',
      );
      return;
    }
    if (_reconnect == null) {
      _log.fine(
        'ws: network appeared types=$types, phase=${_phase.name} → no '
        'reconnect pause to cut short',
      );
      return;
    }
    final left = _pauseLeft();
    _cancelReconnect();
    _log.info(
      'ws network appeared types=$types → reconnecting now instead of '
      'waiting ${left}ms more, attempt=${_failures + 1}',
    );
    unawaited(_open('network appeared'));
  }

  void _begin(String why) {
    if (!_wanted) {
      _log.fine(
        'ws not connecting ($why): '
        '${!_signedIn ? 'no active session, waits for sign-in' : 'app in background, connects on resume'}',
      );
      return;
    }
    if (_phase != WsPhase.off) {
      _log.fine('ws already ${_phase.name} ($why) → no second connection');
      return;
    }
    _failures = 0;
    _dropped = false;
    _refreshedLast = false;
    unawaited(_open(why));
  }

  void _end(String why, String closeReason) {
    _run++;
    final hadReconnect = _cancelReconnect();
    final channel = _channel;
    final age = _ageMs();
    final phase = _phase;
    _detach();
    _phase = WsPhase.off;
    if (channel != null) {
      _closeQuietly(channel, WsCloseCode.normal, closeReason);
      _log.info(
        'ws closed: $why after ${age ?? '-'}ms → '
        'code=${WsCloseCode.normal} reason=$closeReason',
      );
      return;
    }
    if (phase == WsPhase.off) return;
    _log.info(
      'ws off: $why while ${phase.name}'
      '${hadReconnect ? ' → reconnect pause cancelled' : ''}',
    );
  }

  Future<void> _open(String why) async {
    final run = ++_run;
    _phase = WsPhase.connecting;
    final attempt = _failures + 1;
    final from = _clock();
    final Uri url;
    try {
      url = _url();
    } catch (e, st) {
      _phase = WsPhase.off;
      _log.severe(
        'ws not connecting: server address not configured → no realtime '
        'updates, sync runs on its other triggers: ${describeError(e)}',
        e,
        st,
      );
      return;
    }
    final AuthTokens? tokens;
    try {
      tokens = await _readTokens();
    } catch (e, st) {
      if (run != _run) return;
      _retryLater(
        'ws not connecting attempt=$attempt: token store read failed after '
        '${_msSince(from)}ms: ${describeError(e)}',
        error: e,
        stack: st,
      );
      return;
    }
    if (run != _run) return;
    if (tokens == null) {
      _phase = WsPhase.off;
      _log.info(
        'ws not connecting ($why): no session tokens → waits for sign-in',
      );
      return;
    }
    _log.info('ws connecting url=$url attempt=$attempt ($why)');
    final WebSocketChannel channel;
    try {
      channel = await _connect(url, {
        'Authorization': 'Bearer ${tokens.accessToken}',
      });
    } catch (e, st) {
      if (run != _run) return;
      final status = webSocketHandshakeStatus(e);
      if (status == 401) {
        _tokenRejected(
          run,
          tokens.accessToken,
          'handshake answered 401 attempt=$attempt in '
          '${_msSince(from)}ms',
          rightAfterRefresh: _refreshedLast,
        );
        return;
      }
      _retryLater(
        'ws connect failed url=$url attempt=$attempt in '
        '${_msSince(from)}ms${status == null ? '' : ' status=$status'}'
        ': ${describeError(e)}',
        error: e,
        stack: st,
      );
      return;
    }
    if (run != _run) {
      _log.fine(
        'ws connected in ${_msSince(from)}ms after it stopped being '
        'needed → closing it',
      );
      _closeQuietly(channel, WsCloseCode.normal, WsCloseReason.notNeeded);
      return;
    }
    _channel = channel;
    _accessToken = tokens.accessToken;
    _openedAt = _clock();
    _phase = WsPhase.open;
    _log.info('ws connected in ${_msSince(from)}ms url=$url attempt=$attempt');
    _messages = channel.stream.listen(
      (message) => _onMessage(channel, message),
      onError: (Object e, StackTrace st) => _onStreamError(channel, e, st),
      onDone: () => _onDone(channel),
    );
    _armPing();
    if (_dropped) {
      _dropped = false;
      _log.info(
        'ws reconnected after a drop → sync reason=websocket to catch up on '
        'changes missed while disconnected',
      );
      _syncChanged('catch-up after reconnect');
    }
  }

  void _onMessage(WebSocketChannel channel, Object? message) {
    if (!identical(channel, _channel)) return;
    final json = _decode(message);
    switch (json?['type']) {
      case 'changed':
        final ids = json?['budgetIds'];
        final budgetIds = ids is List ? ids.join(',') : '-';
        final cursor = json?['cursor'] ?? '-';
        _log.fine(
          'ws message type=changed budgetIds=[$budgetIds] cursor=$cursor → '
          'sync reason=websocket',
        );
        _syncChanged('changed cursor=$cursor');
      case 'pong':
        final sentAt = _pingSentAt;
        _pingSentAt = null;
        _log.fine(
          'ws message type=pong in '
          '${sentAt == null ? '-' : _msSince(sentAt)}ms',
        );
      default:
        _log.warning('ws message ignored ${_describeMessage(message, json)}');
    }
  }

  void _onStreamError(WebSocketChannel channel, Object error, StackTrace st) {
    if (!identical(channel, _channel)) return;
    _log.warning(
      'ws stream error after ${_ageMs() ?? '-'}ms: '
      '${describeError(error)} → waiting for the close',
      error,
      st,
    );
  }

  void _onDone(WebSocketChannel channel) {
    if (!identical(channel, _channel)) return;
    final age = _age();
    final token = _accessToken;
    final code = channel.closeCode;
    final reason = channel.closeReason;
    _detach();
    _dropped = true;
    _forgetFailuresIfStable(age);
    final details =
        'code=${code ?? '-'} '
        'reason=${reason == null || reason.isEmpty ? '-' : truncateBody(reason, maxBytes: 64)} '
        'after ${age.inMilliseconds}ms';
    switch (code) {
      case WsCloseCode.tokenExpired when token != null:
        _tokenRejected(
          _run,
          token,
          'closed by server $details',
          rightAfterRefresh: _refreshedLast,
        );
      case WsCloseCode.serverShutdown:
        _retryLater(
          'ws closed by server $details: server shutting down',
          level: Level.INFO,
        );
      case WsCloseCode.idleTimeout:
        _retryLater(
          'ws closed by server $details: our pings did not reach the server',
        );
      default:
        _retryLater('ws connection lost $details');
    }
  }

  void _tokenRejected(
    int run,
    String accessToken,
    String cause, {
    required bool rightAfterRefresh,
  }) {
    if (rightAfterRefresh) {
      _retryLater(
        'ws access token rejected again right after a session refresh '
        '($cause)',
      );
      return;
    }
    _log.info(
      'ws access token rejected ($cause) → refreshing session, then '
      'reconnecting',
    );
    unawaited(_refreshThenReconnect(run, accessToken, cause));
  }

  Future<void> _refreshThenReconnect(
    int run,
    String accessToken,
    String cause,
  ) async {
    _phase = WsPhase.refreshing;
    final from = _clock();
    try {
      await _refresh(accessToken);
    } on ApiSessionExpired catch (e) {
      if (run != _run) return;
      _phase = WsPhase.off;
      _log.info(
        'ws session ended while refreshing (${e.reason.name}) in '
        '${_msSince(from)}ms → not reconnecting until the next sign-in',
      );
      return;
    } catch (e, st) {
      if (run != _run) return;
      _retryLater(
        'ws session refresh failed in ${_msSince(from)}ms: '
        '${_describe(e)}',
        error: e,
        stack: st,
      );
      return;
    }
    if (run != _run) {
      _log.fine(
        'ws session refreshed in ${_msSince(from)}ms after the '
        'socket stopped being needed → not reconnecting',
      );
      return;
    }
    _refreshedLast = true;
    _log.info('ws session refreshed in ${_msSince(from)}ms → reconnecting now');
    await _open('access token refreshed');
  }

  void _retryLater(
    String cause, {
    Level level = Level.WARNING,
    Object? error,
    StackTrace? stack,
  }) {
    _failures++;
    _refreshedLast = false;
    final delay = syncRetryDelay(_failures, _random.nextDouble());
    _phase = WsPhase.waiting;
    _log.log(
      level,
      '$cause → reconnect attempt=${_failures + 1} in ${delay.inMilliseconds}ms',
      error,
      stack,
    );
    _reconnect?.cancel();
    final run = _run;
    _reconnectDelay = delay;
    _reconnectFrom = _clock();
    _reconnect = _timer(delay, () {
      _reconnect = null;
      if (run != _run || !_wanted) return;
      _log.info(
        'ws reconnect pause of ${delay.inMilliseconds}ms elapsed → '
        'connecting attempt=${_failures + 1}',
      );
      unawaited(_open('reconnect after pause'));
    });
  }

  void _armPing() {
    _ping?.cancel();
    _ping = _timer(wsPingInterval, _pingTick);
  }

  void _pingTick() {
    _ping = null;
    final channel = _channel;
    if (channel == null) return;
    if (_pingSentAt != null) {
      _lost(
        channel,
        'no pong within ${wsPingInterval.inMilliseconds}ms of the last ping',
      );
      return;
    }
    _pingSentAt = _clock();
    try {
      channel.sink.add(_pingMessage);
    } catch (e, st) {
      _lost(channel, 'ping not sent: ${describeError(e)}', e, st);
      return;
    }
    _log.fine(
      'ws ping sent after ${wsPingInterval.inSeconds}s, waiting for pong',
    );
    _armPing();
  }

  void _lost(
    WebSocketChannel channel,
    String cause, [
    Object? error,
    StackTrace? stack,
  ]) {
    final age = _age();
    _detach();
    _closeQuietly(channel, WsCloseCode.noPong, WsCloseReason.noPong);
    _dropped = true;
    _forgetFailuresIfStable(age);
    _retryLater(
      'ws connection considered dead: $cause, after ${age.inMilliseconds}ms '
      '→ closed code=${WsCloseCode.noPong}',
      error: error,
      stack: stack,
    );
  }

  void _syncChanged(String why) {
    final Future<SyncCycleResult> running;
    try {
      running = _changed();
    } catch (e, st) {
      _log.severe(
        'ws $why: sync reason=websocket did not start: ${describeError(e)}',
        e,
        st,
      );
      return;
    }
    unawaited(
      running.then<void>(
        (_) {},
        onError: (Object e, StackTrace st) => _log.severe(
          'ws $why: sync cycle reason=websocket crashed: ${describeError(e)}',
          e,
          st,
        ),
      ),
    );
  }

  void _forgetFailuresIfStable(Duration age) {
    if (age < wsStableAfter) return;
    _failures = 0;
    _refreshedLast = false;
  }

  void _detach() {
    _ping?.cancel();
    _ping = null;
    _pingSentAt = null;
    final messages = _messages;
    _messages = null;
    if (messages != null) unawaited(messages.cancel());
    _channel = null;
    _accessToken = null;
    _openedAt = null;
  }

  int _msSince(Duration from) => (_clock() - from).inMilliseconds;

  Duration _age() {
    final openedAt = _openedAt;
    return openedAt == null ? Duration.zero : _clock() - openedAt;
  }

  int? _ageMs() => _openedAt == null ? null : _age().inMilliseconds;

  bool _cancelReconnect() {
    final timer = _reconnect;
    if (timer == null) return false;
    timer.cancel();
    _reconnect = null;
    return true;
  }

  int _pauseLeft() {
    final delay = _reconnectDelay?.inMilliseconds ?? 0;
    final from = _reconnectFrom;
    final waited = from == null ? 0 : _msSince(from);
    return math.max(delay - waited, 0);
  }

  void _closeQuietly(WebSocketChannel channel, int code, String reason) {
    unawaited(
      Future<void>.sync(() => channel.sink.close(code, reason)).then<void>(
        (_) {},
        onError: (Object e, StackTrace st) => _log.warning(
          'ws close code=$code reason=$reason failed: ${describeError(e)}',
          e,
          st,
        ),
      ),
    );
  }
}

MonotonicClock _stopwatchClock() {
  final stopwatch = Stopwatch()..start();
  return () => stopwatch.elapsed;
}

Map<String, Object?>? _decode(Object? message) {
  if (message is! String) return null;
  try {
    final json = jsonDecode(message);
    return json is Map<String, Object?> ? json : null;
  } on FormatException {
    return null;
  }
}

String _describeMessage(Object? message, Map<String, Object?>? json) {
  if (message is String) {
    final type = json?['type'];
    return formatContext({
      'kind': 'text',
      'type': type is String ? truncateBody(type, maxBytes: 32) : 'none',
      'size': message.length,
    });
  }
  if (message is List<int>) return 'kind=binary size=${message.length}';
  return 'kind=${message.runtimeType}';
}

String _describe(Object error) => switch (error) {
  final ApiException e => '${e.runtimeType}: ${e.details}',
  final Object e => describeError(e),
};

final webSocketConnectProvider = Provider<WebSocketConnect>(
  (ref) => connectWebSocket,
  name: 'webSocketConnect',
);

final syncWebSocketProvider = Provider<SyncWebSocket>((ref) {
  final socket = SyncWebSocket(
    url: () => webSocketUrl(ref.read(apiConfigProvider)),
    readTokens: () => ref.read(tokenStoreProvider).readTokens(),
    refresh: (accessToken) => ref
        .read(apiClientProvider)
        .refreshRejectedToken(
          path: syncWebSocketPath,
          accessToken: accessToken,
        ),
    changed: () => ref.read(syncTriggersProvider).websocketChanged(),
    connect: ref.watch(webSocketConnectProvider),
  );
  ref.onDispose(socket.dispose);
  return socket;
}, name: 'syncWebSocket');
