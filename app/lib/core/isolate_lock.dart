import 'dart:async';
import 'dart:isolate';
import 'dart:ui' show IsolateNameServer;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

final _log = Logger('lock');

const Duration isolateAckTimeout = Duration(seconds: 5);

const Duration isolateLockRecheck = Duration(seconds: 10);

const String sessionRefreshLockName = 'ru.milionchik.lock.session-refresh';

const String backgroundJobLockName = 'ru.milionchik.lock.background-job';

const Duration _registrationPoll = Duration(milliseconds: 20);

const String _waitMessage = 'wait';
const String _heldMessage = 'held';
const String _releasedMessage = 'released';

final class IsolateLease {
  IsolateLease._(
    this._lock,
    this.owner,
    this._port, {
    required this.waited,
    required this.waitedFor,
  }) {
    _port.listen(_onMessage);
  }

  final IsolateLock _lock;
  final String owner;
  final Duration waited;
  final String? waitedFor;
  final ReceivePort _port;
  final List<SendPort> _waiters = [];
  bool _released = false;

  bool get released => _released;

  void _onMessage(Object? message) {
    if (message is! List<Object?> || message.length < 2) return;
    final reply = message[1];
    if (message[0] != _waitMessage || reply is! SendPort) return;
    if (_released) {
      reply.send(const [_releasedMessage]);
      return;
    }
    _waiters.add(reply);
    reply.send([_heldMessage, owner]);
  }

  void release() {
    if (_released) return;
    _released = true;
    final name = _lock.name;
    if (IsolateNameServer.lookupPortByName(name) == _port.sendPort) {
      IsolateNameServer.removePortNameMapping(name);
    }
    for (final waiter in _waiters) {
      waiter.send(const [_releasedMessage]);
    }
    _log.fine('lock $name released by $owner waiters=${_waiters.length}');
    _waiters.clear();
    _port.close();
  }
}

sealed class _Answer {
  const _Answer();
}

final class _Silent extends _Answer {
  const _Silent();
}

final class _Held extends _Answer {
  const _Held(this.owner, {required this.released});

  final String owner;
  final bool released;
}

final class _Gone extends _Answer {
  const _Gone();
}

enum _Wait { message, closed, moved, timeout }

final class IsolateLock {
  IsolateLock(
    this.name, {
    this.ackTimeout = isolateAckTimeout,
    this.recheck = isolateLockRecheck,
  });

  final String name;
  final Duration ackTimeout;
  final Duration recheck;

  IsolateLease? tryAcquire(String owner) =>
      _register(owner, Duration.zero, null);

  Future<IsolateLease> acquire(String owner) async {
    final sw = Stopwatch()..start();
    String? waitedFor;
    var announced = false;
    while (true) {
      final lease = _register(owner, sw.elapsed, waitedFor);
      if (lease != null) {
        if (waitedFor != null) {
          _log.info(
            'lock $name taken by $owner after waiting '
            '${sw.elapsedMilliseconds}ms for $waitedFor',
          );
        } else {
          _log.fine('lock $name taken by $owner');
        }
        return lease;
      }
      final holder = IsolateNameServer.lookupPortByName(name);
      if (holder == null) {
        await Future<void>.delayed(Duration.zero);
        continue;
      }
      switch (await _ask(holder)) {
        case _Silent():
          if (IsolateNameServer.lookupPortByName(name) == holder) {
            IsolateNameServer.removePortNameMapping(name);
            _log.warning(
              'lock $name: holder ${waitedFor ?? '?'} did not answer in '
              '${ackTimeout.inMilliseconds}ms → its isolate is gone, stale '
              'lock removed, taken over by $owner',
            );
          }
        case _Held(owner: final holderName, :final released):
          waitedFor = holderName;
          if (!announced) {
            announced = true;
            _log.info('lock $name held by $holderName → $owner waits');
          } else if (!released) {
            _log.fine(
              'lock $name still held by $holderName after '
              '${sw.elapsedMilliseconds}ms → $owner keeps waiting',
            );
          }
        case _Gone():
          break;
      }
    }
  }

  Future<String?> holder() async {
    final port = IsolateNameServer.lookupPortByName(name);
    if (port == null) return null;
    final answer = await _ask(port, waitRelease: false);
    return switch (answer) {
      _Held(:final owner, :final released) => released ? null : owner,
      _Silent() || _Gone() => null,
    };
  }

  IsolateLease? _register(String owner, Duration waited, String? waitedFor) {
    final port = ReceivePort('lock $name');
    if (!IsolateNameServer.registerPortWithName(port.sendPort, name)) {
      port.close();
      return null;
    }
    return IsolateLease._(
      this,
      owner,
      port,
      waited: waited,
      waitedFor: waitedFor,
    );
  }

  Future<_Answer> _ask(SendPort holder, {bool waitRelease = true}) async {
    final reply = ReceivePort('lock $name waiter');
    final messages = StreamIterator<Object?>(reply);
    try {
      holder.send([_waitMessage, reply.sendPort]);
      switch (await _next(messages, holder, ackTimeout)) {
        case _Wait.timeout:
          return const _Silent();
        case _Wait.moved || _Wait.closed:
          return const _Gone();
        case _Wait.message:
          break;
      }
      final first = messages.current;
      if (first is! List<Object?> || first.isEmpty) return const _Gone();
      if (first[0] == _releasedMessage) return const _Gone();
      final owner = first.length > 1 ? '${first[1]}' : '?';
      if (!waitRelease) return _Held(owner, released: false);
      final released = await _next(messages, holder, recheck);
      return _Held(owner, released: released != _Wait.timeout);
    } finally {
      await messages.cancel();
      reply.close();
    }
  }

  Future<_Wait> _next(
    StreamIterator<Object?> messages,
    SendPort holder,
    Duration limit,
  ) async {
    final next = messages.moveNext();
    final sw = Stopwatch()..start();
    while (true) {
      final got = await next
          .then<bool?>((v) => v)
          .timeout(_registrationPoll, onTimeout: () => null);
      if (got != null) return got ? _Wait.message : _Wait.closed;
      if (IsolateNameServer.lookupPortByName(name) != holder) {
        return _Wait.moved;
      }
      if (sw.elapsed >= limit) return _Wait.timeout;
    }
  }
}

final class IsolateCoordination {
  const IsolateCoordination({required this.sessionRefresh, this.backgroundJob});

  factory IsolateCoordination.app() => IsolateCoordination(
    sessionRefresh: IsolateLock(sessionRefreshLockName),
    backgroundJob: IsolateLock(backgroundJobLockName),
  );

  factory IsolateCoordination.background() =>
      IsolateCoordination(sessionRefresh: IsolateLock(sessionRefreshLockName));

  final IsolateLock sessionRefresh;
  final IsolateLock? backgroundJob;
}

final isolateCoordinationProvider = Provider<IsolateCoordination?>(
  (ref) => null,
  name: 'isolateCoordination',
);
