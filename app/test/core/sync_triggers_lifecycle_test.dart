import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart' show TableUpdate, UpdateKind;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/core/data_startup.dart';
import 'package:milionchik/core/network_status.dart';
import 'package:milionchik/core/sync_triggers_scope.dart';
import 'package:milionchik/data/api/api_exception.dart';
import 'package:milionchik/data/api/token_store.dart';
import 'package:milionchik/data/db/app_database.dart';
import 'package:milionchik/data/dev_seed.dart';
import 'package:milionchik/data/session/session.dart';
import 'package:milionchik/data/session/session_providers.dart';
import 'package:milionchik/data/session/session_state.dart';
import 'package:milionchik/data/sync/sync_engine.dart';
import 'package:milionchik/data/sync/sync_triggers.dart';

import '../data/api/fake_api_adapter.dart';
import '../data/session/fake_secure_values.dart';

const _user = SessionUser(
  userId: 'user-triggers-1',
  login: 'anya_m',
  displayName: 'Аня',
);

const _session = Session(
  user: _user,
  tokens: AuthTokens(
    accessToken: 'ACCESS-triggers-alpha-bravo',
    refreshToken: 'REFRESH-triggers-charlie-delta',
  ),
);

final class _Rig {
  _Rig(this.tester);

  final WidgetTester tester;
  final List<SyncReason> reasons = [];
  final StreamController<List<ConnectivityResult>> network =
      StreamController<List<ConnectivityResult>>.broadcast();
  final StreamController<Set<TableUpdate>> outbox =
      StreamController<Set<TableUpdate>>.broadcast();
  bool retry = false;
  late SyncTriggers triggers;

  ProviderContainer get container =>
      ProviderScope.containerOf(tester.element(find.byKey(_child)));

  static const _child = Key('child');

  Future<void> mount({bool signedIn = true}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          secureValuesProvider.overrideWithValue(FakeSecureValues()),
          if (signedIn)
            sessionProvider.overrideWithBuild(
              (ref, _) => const SessionActive(_user),
            ),
          networkCheckProvider.overrideWithValue(
            () async => const [ConnectivityResult.wifi],
          ),
          networkChangesProvider.overrideWith((ref) => network.stream),
          outboxWritesProvider.overrideWith((ref) => outbox.stream),
          syncTriggersProvider.overrideWith((ref) {
            final created = SyncTriggers(
              sync: (reason) {
                reasons.add(reason);
                return Future.value(
                  SyncCycleSkipped(
                    reason: reason,
                    elapsed: Duration.zero,
                    why: 'fake engine',
                  ),
                );
              },
              retryScheduled: () => retry,
            );
            ref.onDispose(created.dispose);
            return triggers = created;
          }),
        ],
        child: const SyncTriggersScope(child: SizedBox(key: _child)),
      ),
    );
    await tester.pump();
  }

  Future<void> lifecycle(List<AppLifecycleState> states) async {
    for (final state in states) {
      tester.binding.handleAppLifecycleStateChanged(state);
      await tester.pump();
    }
  }

  Future<void> background() => lifecycle(const [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
  ]);

  Future<void> foreground() => lifecycle(const [
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]);

  Future<void> emit(List<ConnectivityResult> results) async {
    network.add(results);
    await tester.pump();
  }

  Future<void> write() async {
    outbox.add({const TableUpdate('outbox', kind: UpdateKind.insert)});
    await tester.pump();
  }

  Future<void> unmount() async {
    await tester.pumpWidget(const SizedBox());
    await network.close();
    await outbox.close();
  }
}

void main() {
  late LogCapture logs;

  setUp(() => logs = LogCapture());
  tearDown(() => logs.dispose());

  testWidgets('приложение открыто: раз в 60 с reason=periodic; в фоне таймер '
      'не тикает 10 минут; возврат - reason=resume и снова раз в минуту', (
    tester,
  ) async {
    final rig = _Rig(tester);
    await rig.mount();
    expect(rig.reasons, [SyncReason.startup]);
    expect(rig.triggers.periodicScheduled, isTrue);

    await tester.pump(const Duration(seconds: 59));
    expect(rig.reasons, [SyncReason.startup]);
    await tester.pump(const Duration(seconds: 1));
    expect(rig.reasons, [SyncReason.startup, SyncReason.periodic]);
    await tester.pump(const Duration(seconds: 60));
    expect(rig.reasons.where((r) => r == SyncReason.periodic), hasLength(2));

    await rig.background();
    expect(rig.triggers.periodicScheduled, isFalse);
    await tester.pump(const Duration(minutes: 10));
    expect(rig.reasons, hasLength(3));

    await rig.foreground();
    expect(rig.reasons.last, SyncReason.resume);
    await tester.pump(const Duration(seconds: 60));
    expect(rig.reasons, [
      SyncReason.startup,
      SyncReason.periodic,
      SyncReason.periodic,
      SyncReason.resume,
      SyncReason.periodic,
    ]);
    expect(
      logs.linesOf('sync', Level.FINE),
      containsAllInOrder([
        endsWith('sync trigger reason=startup: app started with a session'),
        endsWith(
          'sync trigger reason=periodic: every 60s while the app is open',
        ),
        endsWith(
          'sync triggers: app in background → periodic timer stopped, resume '
          'syncs again',
        ),
        endsWith('sync trigger reason=resume: app back from background'),
      ]),
    );
    await rig.unmount();
  });

  testWidgets('шторка уведомлений (inactive и обратно) - не возврат из фона: '
      'синхронизации нет, таймер идёт', (tester) async {
    final rig = _Rig(tester);
    await rig.mount();

    await rig.lifecycle(const [
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]);
    await tester.pump(const Duration(seconds: 30));

    expect(rig.reasons, [SyncReason.startup]);
    expect(rig.triggers.periodicScheduled, isTrue);
    expect(
      logs.linesOf('sync', Level.FINE),
      contains(
        endsWith(
          'sync triggers: app resumed from inactive, not from background → '
          'no sync',
        ),
      ),
    );
    await rig.unmount();
  });

  testWidgets('сеть: проверка при старте - точка отсчёта; потеря и появление '
      '- reason=network; в фоне появление сети ждёт возврата', (tester) async {
    final rig = _Rig(tester);
    await rig.mount();
    expect(rig.triggers.online, isTrue);

    await rig.emit(const [ConnectivityResult.wifi]);
    await rig.emit(const [ConnectivityResult.none]);
    await rig.emit(const [ConnectivityResult.mobile]);
    expect(rig.reasons, [SyncReason.startup, SyncReason.network]);

    await rig.background();
    await rig.emit(const [ConnectivityResult.none]);
    await rig.emit(const [ConnectivityResult.wifi]);
    expect(rig.reasons, hasLength(2));
    await rig.foreground();
    expect(rig.reasons, [
      SyncReason.startup,
      SyncReason.network,
      SyncReason.resume,
    ]);
    expect(
      logs.linesOf('sync', Level.INFO),
      containsAllInOrder([
        endsWith(
          'network lost types=none → sync waits for network, changes stay in '
          'the queue',
        ),
        endsWith('network appeared types=mobile → sync reason=network'),
        endsWith(
          'network appeared types=wifi while the app is in background → no '
          'sync now, resume runs one',
        ),
      ]),
    );
    expect(
      logs.linesOf('sync', Level.FINE),
      containsAllInOrder([
        endsWith(
          'sync triggers: network online=true types=wifi (first event) → no '
          'sync, the startup sync covers it',
        ),
        endsWith(
          'sync triggers: network changed types=wifi, still online=true → no '
          'sync',
        ),
      ]),
    );
    await rig.unmount();
  });

  testWidgets('пять записей в очередь подряд (по 300 мс) - один запуск '
      'reason=outbox через 1,5 с после последней', (tester) async {
    final rig = _Rig(tester);
    await rig.mount();

    for (var i = 0; i < 5; i++) {
      await rig.write();
      await tester.pump(const Duration(milliseconds: 300));
    }
    await tester.pump(const Duration(milliseconds: 1100));
    expect(rig.reasons, [SyncReason.startup]);
    await tester.pump(const Duration(milliseconds: 100));

    expect(rig.reasons, [SyncReason.startup, SyncReason.outbox]);
    await tester.pump(const Duration(seconds: 5));
    expect(rig.reasons, [SyncReason.startup, SyncReason.outbox]);
    expect(
      logs.linesOf('sync', Level.FINE),
      contains(
        endsWith(
          'sync triggers: outbox delay elapsed, 5 writes merged into one cycle',
        ),
      ),
    );
    await rig.unmount();
  });

  testWidgets('выход из аккаунта останавливает таймер и задержку очереди; '
      'вход - reason=startup и снова раз в минуту', (tester) async {
    final rig = _Rig(tester);
    await rig.mount();
    await rig.write();

    rig.container
        .read(sessionProvider.notifier)
        .ended(SessionEndReason.refreshRejected);
    await tester.pump();
    expect(rig.triggers.periodicScheduled, isFalse);
    expect(rig.triggers.outboxDelayScheduled, isFalse);
    await tester.pump(const Duration(minutes: 3));
    await rig.write();
    await tester.pump(const Duration(seconds: 2));
    expect(rig.reasons, [SyncReason.startup]);

    await rig.container.read(sessionProvider.notifier).save(_session);
    await tester.pump();
    expect(rig.reasons, [SyncReason.startup, SyncReason.startup]);
    await tester.pump(const Duration(seconds: 60));
    expect(rig.reasons.last, SyncReason.periodic);
    expect(
      logs.linesOf('sync', Level.FINE),
      containsAllInOrder([
        endsWith(
          'sync triggers: session active→ended → no syncs until sign-in, '
          'periodic timer stopped, outbox delay dropped (1 write(s) stay in '
          'the queue)',
        ),
        endsWith(
          'sync trigger reason=startup: signed in (session ended→active)',
        ),
      ]),
    );
    await rig.unmount();
  });

  testWidgets('без входа при старте ничего не запускается; движок ждёт '
      'повтора - тик таймера пропускается', (tester) async {
    final rig = _Rig(tester);
    await rig.mount(signedIn: false);
    await tester.pump(const Duration(minutes: 2));
    expect(rig.reasons, isEmpty);
    expect(rig.triggers.periodicScheduled, isFalse);
    await rig.unmount();

    final second = _Rig(tester);
    await second.mount();
    second.retry = true;
    await tester.pump(const Duration(seconds: 60));
    expect(second.reasons, [SyncReason.startup]);
    second.retry = false;
    await tester.pump(const Duration(seconds: 60));
    expect(second.reasons, [SyncReason.startup, SyncReason.periodic]);
    expect(
      logs.linesOf('sync', Level.FINE),
      containsAllInOrder([
        endsWith(
          'sync triggers: no active session at start → no startup sync, '
          'waiting for sign-in',
        ),
        endsWith(
          'sync triggers: periodic tick while the engine waits for its retry '
          'timer after a failure → no extra cycle, the retry runs it',
        ),
      ]),
    );
    await second.unmount();
  });

  testWidgets('appRoot: триггеры синхронизации подключены; без входа старт '
      'ничего не запускает', (tester) async {
    final db = AppDatabase.memory();
    await tester.pumpWidget(
      appRoot(DataReady(db, const DevSeedResult(DevSeedStatus.off))),
    );
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }

    expect(find.byType(SyncTriggersScope), findsOneWidget);
    expect(
      logs.linesOf('sync', Level.INFO),
      contains(contains('sync triggers on: startup, resume, network')),
    );
    expect(
      logs.linesOf('sync', Level.FINE),
      contains(
        endsWith(
          'sync triggers: no active session at start → no startup sync, '
          'waiting for sign-in',
        ),
      ),
    );
    expect(
      logs.linesOf('sync', Level.FINE),
      isNot(contains(contains('sync trigger reason='))),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
    await tester.runAsync(db.close);
  });
}
