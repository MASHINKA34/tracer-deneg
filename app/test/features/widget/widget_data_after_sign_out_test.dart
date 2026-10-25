import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/data/api/api_client.dart';
import 'package:milionchik/data/api/api_exception.dart';
import 'package:milionchik/data/api/api_providers.dart';
import 'package:milionchik/data/api/auth_api.dart';
import 'package:milionchik/data/api/token_store.dart';
import 'package:milionchik/data/session/session_providers.dart';
import 'package:milionchik/data/session/session_state.dart';
import 'package:milionchik/features/auth/account_delete_service.dart';
import 'package:milionchik/features/auth/sign_out_service.dart';

import '../../data/api/fake_api_adapter.dart';
import '../../data/sync/pull_fixture.dart' show pullApiConfig;
import '../auth/session_expired_fixture.dart' show testUnmounting;
import '../profile/profile_harness.dart' show ProfileHarness;
import '../profile/sign_out_fixture.dart' show rowsIn;
import 'widget_update_fixture.dart';

const _signedOutKeys = {'v', 'state', 'theme', 'mood', 'colors'};

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  Future<WidgetRig> mount(
    WidgetTester tester,
    FutureOr<FakeReply> Function(FakeCall call) handler,
  ) async {
    final rig = WidgetRig(tester);
    var rid = 0;
    await rig.mount(
      overrides: [
        apiClientProvider.overrideWith(
          (ref) => ApiClient(
            config: pullApiConfig,
            tokens: MemoryTokenStore(ProfileHarness.tokens),
            adapter: FakeApiAdapter(handler),
            newRequestId: () => 'ridwidgetout${(++rid).toString().padLeft(4, '0')}',
          ),
        ),
      ],
    );
    expect(rig.storage.last.state, 'month');
    return rig;
  }

  void expectSignedOut(WidgetWrite write) {
    expect(write.state, 'signedOut');
    expect(write.json.keys.toSet(), _signedOutKeys);
    expect(write.text, isNot(contains('₽')));
  }

  testUnmounting('выход: пока сервер отвечает на logout, данные уже стёрты - '
      'виджет сразу «Войди в Милиончик», итога 0 ₽ не было', (tester) async {
    final logout = Completer<FakeReply>();
    final rig = await mount(tester, (call) {
      if (call.path.endsWith(logoutPath)) return logout.future;
      throw StateError('unexpected ${call.method} ${call.path}');
    });
    final before = rig.storage.writes.length;

    SignOutOutcome? outcome;
    unawaited(
      rig.container
          .read(signOutServiceProvider)
          .signOut(choice: SignOutChoice.confirm, queueSize: 0)
          .then((o) => outcome = o),
    );
    await rig.settle();
    expect(await tester.runAsync(() => rowsIn(rig.db, 'expenses')), 0);
    expect(rig.container.read(sessionProvider), isA<SessionActive>());
    await rig.time.elapse(const Duration(seconds: 3));

    expect(outcome, isNull);
    final during = rig.storage.writes.sublist(before);
    expect(during, hasLength(1));
    expectSignedOut(during.single);
    expect(
      rig.logs.linesOf('widget', Level.INFO).last,
      contains('state=signedOut theme=system mood=autumn because=account '
          'data cleared by sign-out'),
    );

    logout.complete(const FakeReply(204));
    for (var i = 0; i < 20 && outcome == null; i++) {
      await rig.settle();
    }
    await rig.time.elapse(const Duration(seconds: 3));

    expect(outcome, isA<SignedOut>());
    expect(rig.container.read(sessionProvider), isA<SessionAbsent>());
    for (final write in rig.storage.writes.sublist(before)) {
      expectSignedOut(write);
    }
    expect(rig.storage.last.state, 'signedOut');
  });

  testUnmounting('сессия закончилась: «Войди в Милиончик», траты на телефоне '
      'остались', (tester) async {
    final rig = await mount(
      tester,
      (call) => throw StateError('unexpected ${call.method} ${call.path}'),
    );

    rig.container
        .read(sessionProvider.notifier)
        .ended(SessionEndReason.refreshRejected);
    await rig.settle();
    await rig.time.elapse(const Duration(seconds: 1));

    expectSignedOut(rig.storage.last);
    expect(rig.reasons.last, 'session changed');
    expect(
      rig.logs.linesOf('widget', Level.INFO).last,
      contains('because=session ended'),
    );
    expect(await tester.runAsync(() => rowsIn(rig.db, 'expenses')), 4);
  });

  testUnmounting('удаление аккаунта: после ответа сервера - «Войди в '
      'Милиончик»', (tester) async {
    final rig = await mount(tester, (call) {
      if (call.path.endsWith(accountPath) && call.method == 'DELETE') {
        return const FakeReply(204);
      }
      throw StateError('unexpected ${call.method} ${call.path}');
    });

    AccountDeleteOutcome? outcome;
    unawaited(
      rig.container
          .read(accountDeleteServiceProvider)
          .deleteAccount(password: 'parol-widget-delete')
          .then((o) => outcome = o),
    );
    for (var i = 0; i < 20 && outcome == null; i++) {
      await rig.settle();
    }
    await rig.time.elapse(const Duration(seconds: 3));

    expect(outcome, isA<AccountDeleted>());
    expectSignedOut(rig.storage.last);
    expect(rig.container.read(sessionProvider), isA<SessionAbsent>());
  });
}
