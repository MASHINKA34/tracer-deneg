import 'dart:isolate';
import 'dart:ui' show IsolateNameServer;

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/core/isolate_lock.dart';

import '../data/api/fake_api_adapter.dart';

var _names = 0;

String _uniqueName() => 'test.lock.${_names++}';

Future<void> _holdInIsolate((String, SendPort) message) async {
  final (name, ready) = message;
  final lease = await IsolateLock(name).acquire('worker isolate');
  final release = ReceivePort();
  ready.send(release.sendPort);
  await release.first;
  lease.release();
  release.close();
}

Future<void> _until(bool Function() done) async {
  final sw = Stopwatch()..start();
  while (!done()) {
    if (sw.elapsed > const Duration(seconds: 10)) {
      throw StateError('condition not reached in 10s');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  late LogCapture logs;

  setUp(() => logs = LogCapture());
  tearDown(() => logs.dispose());

  test(
    'второй ждёт, пока первый не отпустит, и получает замок после',
    () async {
      final name = _uniqueName();
      final lock = IsolateLock(name);
      final first = await lock.acquire('app sync');
      expect(lock.tryAcquire('background job'), isNull);

      var taken = false;
      final second = lock.acquire('background job').then((lease) {
        taken = true;
        return lease;
      });
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(taken, isFalse);
      expect(await lock.holder(), 'app sync');

      first.release();
      final lease = await second;
      expect(taken, isTrue);
      expect(lease.waitedFor, 'app sync');
      expect(await lock.holder(), 'background job');
      lease.release();
      expect(await lock.holder(), isNull);
      expect(IsolateNameServer.lookupPortByName(name), isNull);
      expect(
        logs.linesOf('lock'),
        containsAllInOrder([
          endsWith('lock $name held by app sync → background job waits'),
          contains('lock $name taken by background job after waiting'),
        ]),
      );
    },
  );

  test('замок из другого изолята: ждём до его освобождения', () async {
    final name = _uniqueName();
    final ready = ReceivePort();
    await Isolate.spawn(_holdInIsolate, (name, ready.sendPort));
    final release = await ready.first as SendPort;
    ready.close();

    final lock = IsolateLock(name);
    expect(await lock.holder(), 'worker isolate');
    var taken = false;
    final waiting = lock.acquire('app sync').then((lease) {
      taken = true;
      return lease;
    });
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(taken, isFalse);

    release.send(null);
    final lease = await waiting;
    expect(lease.waitedFor, 'worker isolate');
    lease.release();
  });

  test(
    'владелец не отвечает (изолят умер) - замок снимается и берётся',
    () async {
      final name = _uniqueName();
      final dead = ReceivePort();
      expect(
        IsolateNameServer.registerPortWithName(dead.sendPort, name),
        isTrue,
      );
      dead.close();

      final lock = IsolateLock(
        name,
        ackTimeout: const Duration(milliseconds: 50),
      );
      final lease = await lock.acquire('app sync');
      expect(lease.owner, 'app sync');
      expect(
        logs.linesOf('lock', Level.WARNING),
        contains(
          endsWith(
            'lock $name: holder ? did not answer in 50ms → its isolate is '
            'gone, stale lock removed, taken over by app sync',
          ),
        ),
      );
      lease.release();
    },
  );

  test(
    'долгое удержание: ожидающий переспрашивает и не крадёт замок',
    () async {
      final name = _uniqueName();
      final lock = IsolateLock(
        name,
        ackTimeout: const Duration(milliseconds: 200),
        recheck: const Duration(milliseconds: 30),
      );
      final first = await lock.acquire('background job');
      var taken = false;
      final second = lock.acquire('app sync').then((lease) {
        taken = true;
        return lease;
      });
      await _until(
        () => logs
            .linesOf('lock', Level.FINE)
            .any((l) => l.contains('still held by background job after')),
      );
      expect(taken, isFalse);
      expect(await lock.holder(), 'background job');
      first.release();
      (await second).release();
      expect(
        logs.linesOf('lock', Level.FINE),
        contains(contains('still held by background job after')),
      );
      expect(logs.linesOf('lock', Level.WARNING), isEmpty);
    },
  );

  test('владелец отпустил, пока вопрос был в пути: ожидающий видит снятую '
      'регистрацию и берёт замок, не дожидаясь таймаута ответа', () async {
    final name = _uniqueName();
    final silent = ReceivePort();
    expect(
      IsolateNameServer.registerPortWithName(silent.sendPort, name),
      isTrue,
    );
    final lock = IsolateLock(name, ackTimeout: const Duration(seconds: 3));

    final sw = Stopwatch()..start();
    final waiting = lock.acquire('app sync');
    await Future<void>.delayed(const Duration(milliseconds: 60));
    IsolateNameServer.removePortNameMapping(name);
    silent.close();
    final lease = await waiting;

    expect(sw.elapsed, lessThan(const Duration(seconds: 1)));
    expect(logs.linesOf('lock', Level.WARNING), isEmpty);
    lease.release();
  });
}
