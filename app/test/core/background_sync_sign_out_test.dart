import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/core/clock.dart';
import 'package:milionchik/core/network_status.dart';
import 'package:milionchik/core/sync_triggers_scope.dart';
import 'package:milionchik/data/api/api_client.dart';
import 'package:milionchik/data/api/api_config.dart';
import 'package:milionchik/data/api/api_providers.dart';
import 'package:milionchik/data/db/app_database.dart';
import 'package:milionchik/data/providers.dart';
import 'package:milionchik/data/session/session.dart';
import 'package:milionchik/data/session/session_providers.dart';
import 'package:milionchik/data/session/session_state.dart';
import 'package:milionchik/data/session/session_store.dart';
import 'package:milionchik/data/sync/background_job.dart';
import 'package:milionchik/data/sync/background_sync.dart';
import 'package:milionchik/data/sync/sync_engine.dart';
import 'package:milionchik/data/sync/sync_triggers.dart';
import 'package:milionchik/data/sync/sync_websocket.dart';
import 'package:milionchik/features/auth/sign_out_service.dart';

import '../data/api/fake_api_adapter.dart';
import '../data/session/fake_secure_values.dart';
import '../data/sync/background_sync_fixture.dart';
import '../data/sync/sync_websocket_fixture.dart';
import '../features/auth/session_expired_fixture.dart' show testUnmounting;
import '../features/profile/profile_fixture.dart';
import '../features/profile/profile_harness.dart' show ProfileHarness;
import '../features/profile/sign_out_fixture.dart';
import '../support/app_scope.dart';

final class _Rig {
  _Rig(this.tester);

  final WidgetTester tester;
  final FakeScheduler scheduler = FakeScheduler();
  final FakeConnector connector = FakeConnector()..autoPong = true;
  final StreamController<List<ConnectivityResult>> network =
      StreamController<List<ConnectivityResult>>.broadcast();
  late final AppDatabase db = openTestDatabase();
  late final FakeApiAdapter adapter = FakeApiAdapter((call) {
    if (call.path.endsWith('/auth/logout')) return const FakeReply(204);
    throw StateError('unexpected ${call.method} ${call.path}');
  });
  late final LogCapture logs = LogCapture();

  static const _child = Key('child');

  ProviderContainer get container =>
      ProviderScope.containerOf(tester.element(find.byKey(_child)));

  Future<void> mount() async {
    addTearDown(logs.dispose);
    await tester.runAsync(() => ProfileFixture.mockup(db));
    final values = FakeSecureValues();
    await tester.runAsync(
      () => SessionStore(
        values,
      ).save(const Session(user: profileUser, tokens: ProfileHarness.tokens)),
    );
    final config = ApiConfig.resolve(define: '', debugBuild: true);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          clockProvider.overrideWithValue(Clock(now: () => testNow)),
          secureValuesProvider.overrideWithValue(values),
          sessionProvider.overrideWithBuild(
            (ref, _) => const SessionActive(profileUser),
          ),
          apiClientProvider.overrideWith(
            (ref) => ApiClient(
              config: config,
              tokens: ref.watch(tokenStoreProvider),
              adapter: adapter,
              newRequestId: () => 'ridbgsignout0001',
            ),
          ),
          webSocketConnectProvider.overrideWithValue(connector.call),
          networkCheckProvider.overrideWithValue(
            () async => const [ConnectivityResult.wifi],
          ),
          networkChangesProvider.overrideWith((ref) => network.stream),
          syncTriggersProvider.overrideWith((ref) {
            final created = SyncTriggers(
              sync: (reason) async => SyncCycleSkipped(
                reason: reason,
                elapsed: Duration.zero,
                why: 'fake engine',
              ),
            );
            ref.onDispose(created.dispose);
            return created;
          }),
          backgroundSyncProvider.overrideWith(
            (ref) => BackgroundSync(
              scheduler: scheduler,
              queueSize: () => ref.read(outboxQueueProvider).count(),
              job: () => BackgroundJob.from(ref.read),
            ),
          ),
        ],
        child: const SyncTriggersScope(child: SizedBox(key: _child)),
      ),
    );
    await settle(() => scheduler.calls.isNotEmpty);
  }

  Future<void> settle([bool Function()? until]) async {
    for (var i = 0; i < 4 || (until != null && !until() && i < 200); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
  }

  Future<void> lifecycle(List<AppLifecycleState> states) async {
    for (final state in states) {
      tester.binding.handleAppLifecycleStateChanged(state);
      await tester.pump();
    }
  }

  Future<void> close() async {
    await tester.pumpWidget(const SizedBox());
    await network.close();
  }
}

void main() {
  testUnmounting('вход есть: периодическая задача в расписании; приложение в '
      'фоне с двумя неотправленными - разовая задача с сетью', (tester) async {
    final rig = _Rig(tester);
    await rig.mount();
    expect(rig.scheduler.calls, ['schedule $periodicSyncUniqueName']);

    await tester.runAsync(() => addUnsyncedExpenses(rig.db, 2));
    await rig.lifecycle(const [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]);
    await rig.settle(
      () => rig.scheduler.calls.contains('schedule $pendingSyncUniqueName'),
    );

    final once = rig.scheduler.scheduled.last;
    expect(once.uniqueName, pendingSyncUniqueName);
    expect(once.requiresNetwork, isTrue);
    expect(once.reason, 'app went to background with 2 unsent change(s)');
    await rig.close();
  });

  testUnmounting('выход из аккаунта: после очистки и logout обе фоновые '
      'задачи отменены', (tester) async {
    final rig = _Rig(tester);
    await rig.mount();

    final outcome = await tester.runAsync(
      () => rig.container
          .read(signOutServiceProvider)
          .signOut(choice: SignOutChoice.confirm, queueSize: 0),
    );
    await rig.settle(
      () => rig.scheduler.calls.contains('cancel $pendingSyncUniqueName'),
    );

    expect(outcome, isA<SignedOut>());
    expect(rig.container.read(sessionProvider), isA<SessionAbsent>());
    expect(rig.scheduler.calls, [
      'schedule $periodicSyncUniqueName',
      'cancel $periodicSyncUniqueName',
      'cancel $pendingSyncUniqueName',
    ]);
    expect(
      rig.logs.linesOf('bg', Level.INFO).last,
      contains(
        'background tasks cancelled ru.milionchik.sync.periodic, '
        'ru.milionchik.sync.pending (session active→absent',
      ),
    );
    await rig.close();
  });
}
