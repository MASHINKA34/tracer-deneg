import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart' show TableUpdate;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/core/network_status.dart';
import 'package:milionchik/core/sync_triggers_scope.dart';
import 'package:milionchik/data/api/api_exception.dart';
import 'package:milionchik/data/api/api_providers.dart';
import 'package:milionchik/data/api/token_store.dart';
import 'package:milionchik/data/session/session.dart';
import 'package:milionchik/data/session/session_providers.dart';
import 'package:milionchik/data/session/session_state.dart';
import 'package:milionchik/data/sync/sync_engine.dart';
import 'package:milionchik/data/sync/sync_triggers.dart';
import 'package:milionchik/data/sync/sync_websocket.dart';

import '../data/api/fake_api_adapter.dart';
import '../data/session/fake_secure_values.dart';
import '../data/sync/sync_websocket_fixture.dart';

const _user = SessionUser(
  userId: 'user-socket-1',
  login: 'anya_m',
  displayName: 'Аня',
);

const _tokens = AuthTokens(
  accessToken: 'ACCESS-lifecycle-golf-hotel-india',
  refreshToken: 'REFRESH-lifecycle-juliet-kilo-lima',
);

final class _Rig {
  _Rig(this.tester);

  final WidgetTester tester;
  final FakeConnector connector = FakeConnector()..autoPong = true;
  final List<SyncReason> reasons = [];
  final StreamController<List<ConnectivityResult>> network =
      StreamController<List<ConnectivityResult>>.broadcast();
  final StreamController<Set<TableUpdate>> outbox =
      StreamController<Set<TableUpdate>>.broadcast();

  static const _child = Key('child');

  ProviderContainer get container =>
      ProviderScope.containerOf(tester.element(find.byKey(_child)));

  SyncWebSocket get socket => container.read(syncWebSocketProvider);

  Future<void> mount() async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          secureValuesProvider.overrideWithValue(FakeSecureValues()),
          sessionProvider.overrideWithBuild(
            (ref, _) => const SessionActive(_user),
          ),
          tokenStoreProvider.overrideWithValue(MemoryTokenStore(_tokens)),
          webSocketConnectProvider.overrideWithValue(connector.call),
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
            );
            ref.onDispose(created.dispose);
            return created;
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

  Future<void> unmount() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await network.close();
    await outbox.close();
  }
}

void _testMounted(String description, Future<void> Function(_Rig rig) body) {
  testWidgets(description, (tester) async {
    final rig = _Rig(tester);
    try {
      await body(rig);
    } finally {
      await rig.unmount();
    }
  });
}

void main() {
  late LogCapture logs;

  setUp(() => logs = LogCapture());
  tearDown(() => logs.dispose());

  _testMounted('на экране подключено с токеном; changed → синхронизация '
      'reason=websocket через триггеры; в фоне сокет закрыт и 10 минут не '
      'подключается; возврат - подключение снова', (rig) async {
    await rig.mount();
    expect(rig.connector.calls, 1);
    expect(rig.connector.bearers.single, _tokens.accessToken);
    expect(
      rig.connector.urls.single.toString(),
      'ws://10.0.2.2:8080/api/v1/ws',
    );
    expect(rig.socket.phase, WsPhase.open);
    expect(rig.reasons, [SyncReason.startup]);

    rig.connector.last.changed(['budget-family'], 501);
    await rig.tester.pump();
    expect(rig.reasons, [SyncReason.startup, SyncReason.websocket]);

    final first = rig.connector.last;
    await rig.background();
    expect(first.closedByClient, isTrue);
    expect(first.clientCloseCode, 1000);
    expect(first.clientCloseReason, 'app_in_background');
    expect(rig.socket.phase, WsPhase.off);
    expect(
      logs.linesOf('ws', Level.INFO).last,
      contains('ws closed: app in background after '),
    );

    await rig.tester.pump(const Duration(minutes: 10));
    expect(rig.connector.calls, 1);

    await rig.foreground();
    expect(rig.connector.calls, 2);
    expect(rig.socket.phase, WsPhase.open);
    expect(rig.reasons.last, SyncReason.resume);
    await rig.tester.pump(const Duration(seconds: 90));
    expect(rig.connector.last.pings, 3);
    expect(rig.connector.calls, 2);
  });

  _testMounted('сессия закончилась - сокет закрыт (signed_out) без '
      'переподключения; вход снова - подключение; размонтирование '
      'закрывает', (rig) async {
    await rig.mount();
    final first = rig.connector.last;

    rig.container
        .read(sessionProvider.notifier)
        .ended(SessionEndReason.refreshRejected);
    await rig.tester.pump();
    expect(first.clientCloseReason, 'signed_out');
    expect(rig.socket.phase, WsPhase.off);
    await rig.tester.pump(const Duration(minutes: 5));
    expect(rig.connector.calls, 1);

    await rig.container
        .read(sessionProvider.notifier)
        .save(const Session(user: _user, tokens: _tokens));
    await rig.tester.pump();
    expect(rig.connector.calls, 2);
    expect(rig.socket.phase, WsPhase.open);

    final second = rig.connector.last;
    await rig.tester.pumpWidget(const SizedBox());
    await rig.tester.pump();
    expect(second.closedByClient, isTrue);
    expect(second.clientCloseCode, 1000);
  });
}
