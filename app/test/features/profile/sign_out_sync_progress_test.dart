import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/core/auth_gate.dart';
import 'package:milionchik/data/session/session_providers.dart';
import 'package:milionchik/data/session/session_state.dart';
import 'package:milionchik/features/auth/login_screen.dart';
import 'package:milionchik/ui/components/button.dart';
import 'package:milionchik/ui/components/dialog.dart';

import '../../data/api/fake_api_adapter.dart';
import '../auth/session_expired_fixture.dart' show testUnmounting;
import 'profile_harness.dart';
import 'sign_out_fixture.dart';

final class _BatchServer {
  final List<int> batches = [];
  final Completer<void> secondBatch = Completer<void>();
  bool offline = true;

  Future<FakeReply> handle(FakeCall call) async {
    if (call.path.endsWith('/auth/logout')) return const FakeReply(204);
    if (!call.path.endsWith('/sync/push')) {
      throw StateError('unexpected ${call.method} ${call.path}');
    }
    final changes = call.json['changes']! as List<Object?>;
    batches.add(changes.length);
    if (batches.length == 2) {
      await secondBatch.future;
      if (offline) throw const SocketException('Network is unreachable');
    }
    return FakeReply.json(200, {
      'applied': [for (final c in changes) (c! as Map<String, Object?>)['id']],
      'rejected': const <Object?>[],
      'cursor': 900 + batches.length,
    });
  }
}

Finder _dialogButton(String label) => find.descendant(
  of: find.byType(AppDialog),
  matching: find.widgetWithText(AppButton, label),
);

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testUnmounting('«Синхронизировать» идёт через движок с прогрессом: пачки '
      'по 200, в заголовке остаток 450 → 250, кнопка «Отправляем…»; обрыв '
      'на второй пачке — диалог остаётся с остатком и ошибкой; повтор — '
      'выход', (tester) async {
    final server = _BatchServer();
    final h = await ProfileHarness.start(
      tester,
      server: server.handle,
      overrides: [signInRequiredProvider.overrideWithValue(true)],
    );
    await tester.runAsync(() => addUnsyncedExpenses(h.db, 450));
    await h.openProfile();
    await h.tap(h.row('Выйти'));
    expect(find.text('450 трат ещё не на сервере'), findsOneWidget);

    await h.tap(_dialogButton('Синхронизировать'));

    expect(server.batches, [200, 200]);
    expect(find.text('250 трат ещё не на сервере'), findsOneWidget);
    expect(find.text('450 трат ещё не на сервере'), findsNothing);
    final sending = tester.widget<AppButton>(_dialogButton('Отправляем…'));
    expect(sending.onPressed, isNull);
    expect(
      h.linesOf('auth', Level.FINE),
      contains(
        endsWith(
          'sign-out dialog: sending through the sync engine, queue 450 → '
          '250 left',
        ),
      ),
    );

    server.secondBatch.complete();
    await h.settle();

    expect(find.byType(AppDialog), findsOneWidget);
    expect(find.text('250 трат ещё не на сервере'), findsOneWidget);
    expect(
      find.text(
        'Нет связи с сервером. Проверь интернет и попробуй ещё раз. '
        'Если выйти, эти траты пропадут с телефона.',
      ),
      findsOneWidget,
    );
    expect(
      tester.widget<AppButton>(_dialogButton('Синхронизировать')).onPressed,
      isNotNull,
    );
    expect(h.container.read(sessionProvider), isA<SessionActive>());
    expect(await tester.runAsync(() => rowsIn(h.db, 'outbox')), 250);

    server.offline = false;
    await h.tap(_dialogButton('Синхронизировать'));

    expect(server.batches, [200, 200, 200, 50]);
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(h.container.read(sessionProvider), isA<SessionAbsent>());
    expect(
      h.linesOf('auth', Level.INFO),
      contains(
        matches(
          r'sign-out sync ok applied=250 rejected=0 in \d+ms → '
          r'signing out$',
        ),
      ),
    );
  });
}
