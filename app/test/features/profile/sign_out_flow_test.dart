import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/core/auth_gate.dart';
import 'package:milionchik/data/providers.dart';
import 'package:milionchik/data/repositories/prefs_repository.dart';
import 'package:milionchik/data/session/session_providers.dart';
import 'package:milionchik/data/session/session_state.dart';
import 'package:milionchik/features/auth/login_screen.dart';
import 'package:milionchik/features/profile/profile_screen.dart';
import 'package:milionchik/ui/components/button.dart';
import 'package:milionchik/ui/components/dialog.dart';

import '../../data/api/fake_api_adapter.dart';
import 'profile_harness.dart';
import 'sign_out_fixture.dart';

final class _Server {
  _Server({this.push, this.logout});

  final FakeReply Function(FakeCall call)? push;
  final FakeReply Function(FakeCall call)? logout;
  final List<String> order = [];

  FakeReply handle(FakeCall call) {
    order.add('${call.method} ${call.path}');
    if (call.path.endsWith('/sync/push')) {
      final handler = push;
      if (handler == null) throw StateError('push not expected');
      return handler(call);
    }
    if (call.path.endsWith('/auth/logout')) {
      return (logout ?? (_) => const FakeReply(204))(call);
    }
    throw StateError('unexpected ${call.method} ${call.path}');
  }
}

FakeReply _applyAll(FakeCall call) {
  final changes = call.json['changes']! as List<Object?>;
  return FakeReply.json(200, {
    'applied': [for (final c in changes) (c! as Map<String, Object?>)['id']],
    'rejected': const <Object?>[],
    'cursor': 120,
  });
}

Never _offline(FakeCall call) =>
    throw const SocketException('Network is unreachable');

Finder _dialogButton(String label) => find.descendant(
  of: find.byType(AppDialog),
  matching: find.widgetWithText(AppButton, label),
);

Future<ProfileHarness> _open(
  WidgetTester tester, {
  required _Server server,
  int unsynced = 0,
  bool signInRequired = true,
}) async {
  final h = await ProfileHarness.start(
    tester,
    server: server.handle,
    overrides: [
      if (signInRequired) signInRequiredProvider.overrideWithValue(true),
    ],
  );
  await tester.runAsync(() async {
    await DriftPrefsRepository(h.db).setString(PrefKeys.themeMode, 'dark');
    await DriftPrefsRepository(h.db).setString(PrefKeys.localUserId, 'u-1');
    if (unsynced > 0) await addUnsyncedExpenses(h.db, unsynced);
  });
  await h.openProfile();
  await h.tap(h.row('Выйти'));
  return h;
}

Future<void> _expectSignedOut(ProfileHarness h) async {
  expect(find.byType(LoginScreen), findsOneWidget);
  expect(find.byType(ProfileScreen), findsNothing);
  expect(find.byType(AppDialog), findsNothing);
  expect(h.container.read(sessionProvider), isA<SessionAbsent>());
  final counts = (await h.tester.runAsync(
    () async => {
      for (final table in const [
        'budgets',
        'budget_members',
        'member_profiles',
        'categories',
        'expenses',
        'recurring_rules',
        'outbox',
      ])
        table: await rowsIn(h.db, table),
      'stored session': await h.container
          .read(sessionStoreProvider)
          .read()
          .then((s) => s == null ? 0 : 1),
    },
  ))!;
  expect(counts.values.toSet(), {0}, reason: '$counts');
  final prefs = (await h.tester.runAsync(
    () => h.db.select(h.db.localPrefs).get(),
  ))!;
  expect({for (final p in prefs) p.key: p.value}, {PrefKeys.themeMode: 'dark'});
}

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testWidgets('пустая очередь: подтверждение без «Синхронизировать», '
      '«Выйти» → logout на сервере, база и сессия стёрты, экран входа', (
    tester,
  ) async {
    final server = _Server();
    final h = await _open(tester, server: server);

    expect(find.text('Выйти из аккаунта?'), findsOneWidget);
    expect(find.text('Синхронизировать'), findsNothing);
    expect(find.text('Выйти и потерять'), findsNothing);
    expect(_dialogButton('Отмена'), findsOneWidget);

    await h.tap(_dialogButton('Выйти'));

    expect(server.order, ['POST /api/v1/auth/logout']);
    expect(
      h.adapter.callsTo('/auth/logout').single.header('Authorization'),
      'Bearer ${ProfileHarness.tokens.accessToken}',
    );
    await _expectSignedOut(h);
    final auth = h.linesOf('auth', Level.INFO);
    expect(
      auth,
      contains(
        matches(
          r'sign-out tap: queue=0 → confirm dialog '
          r'\(counted in \d+ms\)$',
        ),
      ),
    );
    expect(
      auth,
      contains(
        contains(
          'sign-out started choice=confirm queue=0 '
          'userId=user-server-77',
        ),
      ),
    );
    expect(
      auth,
      contains(
        matches(
          r'sign-out done choice=confirm queue=0 '
          r'userId=user-server-77 cleared: \d+ rows, tokens, account prefs '
          r'\[localUserId\] serverSession=revoked in \d+ms → sign-in screen$',
        ),
      ),
    );
  });

  testWidgets('непустая очередь: диалог 42:4321 с числом, «Выйти и '
      'потерять» → push не вызывается, база и сессия стёрты, экран входа', (
    tester,
  ) async {
    final server = _Server();
    final h = await _open(tester, server: server, unsynced: 3);

    expect(find.text('3 траты ещё не на сервере'), findsOneWidget);
    expect(
      find.text(
        'Сейчас нет связи. Если выйти, эти траты пропадут с телефона. '
        'Подожди сеть — мы отправим их сами.',
      ),
      findsOneWidget,
    );
    expect(_dialogButton('Синхронизировать'), findsOneWidget);
    expect(find.text('Выйти из аккаунта?'), findsNothing);

    await h.tap(_dialogButton('Выйти и потерять'));

    expect(server.order, ['POST /api/v1/auth/logout']);
    await _expectSignedOut(h);
    expect(
      h.linesOf('auth', Level.INFO),
      contains(
        endsWith(
          'sign-out started choice=discard queue=3 '
          'userId=user-server-77 → 3 unsynced change(s) dropped with the '
          'local data',
        ),
      ),
    );
  });

  testWidgets('logout без сети не мешает: соединение не открылось → всё '
      'равно вышли, на сервере сессия не отозвана, warn в логе', (
    tester,
  ) async {
    final server = _Server(logout: _offline);
    final h = await _open(tester, server: server, unsynced: 1);

    await h.tap(_dialogButton('Выйти и потерять'));

    await _expectSignedOut(h);
    expect(
      h.linesOf('auth', Level.WARNING),
      contains(
        matches(
          r'sign-out: server logout failed ApiNetworkFailure: '
          r'connection .* rid=ridprofile000001 after \d+ms → continuing, '
          r'signing out on the phone only',
        ),
      ),
    );
    expect(
      h.linesOf('auth', Level.INFO),
      contains(contains('serverSession=not revoked')),
    );
  });

  testWidgets('«Синхронизировать»: очередь уходит push-ем, затем выход', (
    tester,
  ) async {
    final server = _Server(push: _applyAll);
    final h = await _open(tester, server: server, unsynced: 2);

    await h.tap(_dialogButton('Синхронизировать'));

    expect(server.order, [
      'POST /api/v1/sync/push',
      'POST /api/v1/auth/logout',
    ]);
    final pushed = h.adapter.callsTo('/sync/push').single.json;
    expect(pushed['batchId'], isNotEmpty);
    expect(
      [
        for (final c in pushed['changes']! as List<Object?>)
          if (c case {'entity': final Object e, 'op': final Object op}) (e, op),
      ],
      [('expense', 'upsert'), ('expense', 'upsert')],
    );
    await _expectSignedOut(h);
    final auth = h.linesOf('auth', Level.INFO);
    expect(
      auth,
      contains(
        endsWith(
          'sign-out dialog choice=sync queue=2 '
          '→ sending the queue before sign-out',
        ),
      ),
    );
    expect(
      auth,
      contains(
        matches(
          r'sign-out sync ok applied=2 rejected=0 '
          r'in \d+ms → signing out$',
        ),
      ),
    );
  });

  testWidgets('«Синхронизировать» без сети: текст ошибки в диалоге, диалог '
      'остаётся, траты и сессия на месте, logout не вызывался', (tester) async {
    final server = _Server(push: _offline);
    final h = await _open(tester, server: server, unsynced: 3);

    await h.tap(_dialogButton('Синхронизировать'));

    expect(find.byType(AppDialog), findsOneWidget);
    expect(find.text('3 траты ещё не на сервере'), findsOneWidget);
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
    expect(server.order, ['POST /api/v1/sync/push']);
    expect(h.container.read(sessionProvider), isA<SessionActive>());
    expect(
      await tester.runAsync(
        () async =>
            (await rowsIn(h.db, 'outbox'), await rowsIn(h.db, 'expenses')),
      ),
      (3, 3),
    );
    expect(
      h.linesOf('auth', Level.INFO),
      contains(contains('sign-out sync failed ApiNetworkFailure: connection')),
    );
  });

  testWidgets('«Отмена» и «назад»: диалог закрыт, ничего не стёрто', (
    tester,
  ) async {
    final server = _Server();
    final h = await _open(tester, server: server, unsynced: 1);

    await tester.binding.handlePopRoute();
    await h.settle();
    expect(find.byType(AppDialog), findsNothing);

    await h.tap(h.row('Выйти'));
    await tester.runAsync(
      () => h.container.read(outboxQueueProvider).remove([1]),
    );
    await h.settle();
    expect(find.text('1 трата ещё не на сервере'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await h.settle();
    await h.tap(h.row('Выйти'));
    expect(find.text('Выйти из аккаунта?'), findsOneWidget);
    await h.tap(_dialogButton('Отмена'));

    expect(find.byType(AppDialog), findsNothing);
    expect(find.byType(ProfileScreen), findsOneWidget);
    expect(server.order, isEmpty);
    expect(h.container.read(sessionProvider), isA<SessionActive>());
    expect(await tester.runAsync(() => rowsIn(h.db, 'expenses')), 1);
    final auth = h.linesOf('auth', Level.INFO);
    expect(
      auth,
      contains(
        endsWith(
          'sign-out dialog choice=dismissed queue=1 → staying '
          'signed in, nothing cleared',
        ),
      ),
    );
    expect(
      auth,
      contains(
        endsWith(
          'sign-out dialog choice=cancel queue=0 → staying '
          'signed in, nothing cleared',
        ),
      ),
    );
  });

  testWidgets('без обязательного входа (демо DEV_SEED) после выхода тоже '
      'экран входа', (tester) async {
    final server = _Server();
    final h = await _open(tester, server: server, signInRequired: false);

    await h.tap(_dialogButton('Выйти'));

    await _expectSignedOut(h);
    expect(
      h.linesOf('profile'),
      contains(
        endsWith(
          'profile signed out, sign-in not forced by the gate '
          '→ /auth/login',
        ),
      ),
    );
  });

  testWidgets('логи выхода без токенов, логина и комментариев трат', (
    tester,
  ) async {
    final server = _Server(push: _applyAll);
    final h = await _open(tester, server: server, unsynced: 2);

    await h.tap(_dialogButton('Синхронизировать'));

    await _expectSignedOut(h);
    final text = h.logs.text;
    expect(text, contains('sign-out done choice=sync'));
    expect(text, isNot(contains(ProfileHarness.tokens.accessToken)));
    expect(text, isNot(contains(ProfileHarness.tokens.refreshToken)));
    expect(text, isNot(contains('anya_m')));
    expect(text, isNot(contains(unsyncedComment)));
  });
}
