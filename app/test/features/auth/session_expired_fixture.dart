import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:milionchik/core/auth_gate.dart';
import 'package:milionchik/data/db/app_database.dart';
import 'package:milionchik/features/auth/login_screen.dart';
import 'package:milionchik/ui/components/button.dart';
import 'package:milionchik/ui/components/dialog.dart';
import 'package:shared/shared.dart';

import '../../data/api/fake_api_adapter.dart';
import '../../data/sync/pull_fixture.dart' show serverPersonal;
import '../profile/profile_fixture.dart';
import '../profile/profile_harness.dart';
import '../profile/sign_out_fixture.dart';
import 'auth_harness.dart' show signedIn;

const String userPassword = 'parol-zulu-yankee-xray';

const String wrongPassword = 'parol-wrong-whiskey';

const String otherLogin = 'boris_k';

const String otherUserId = 'user-server-88';

const String sameAccess = 'ACCESS-same-alfa-bravo-charlie';

const String otherAccess = 'ACCESS-other-delta-echo-foxtrot';

const String newRefresh = 'REFRESH-new-golf-hotel-india';

const String recoveryCodeText = 'ABCDEFGHJKMN';

const int keptCursor = 42;

final class ExpiredSessionServer {
  final List<String> order = [];
  final Map<String, List<int>> pulls = {};

  FakeReply handle(FakeCall call) {
    order.add('${call.method} ${call.path}');
    final path = call.path;
    if (path.endsWith('/sync/push')) {
      final bearer = call.header('Authorization');
      if (bearer == 'Bearer ${ProfileHarness.tokens.accessToken}') {
        return FakeReply.error(401, 'unauthorized');
      }
      final request = SyncPushRequest.fromJson(call.json);
      return FakeReply.json(
        200,
        SyncPushResponse(
          applied: [for (final c in request.changes) c.id],
          rejected: const [],
          cursor: 0,
        ).toJson(),
      );
    }
    if (path.endsWith('/sync/pull')) {
      final bearer = call.header('Authorization');
      if (bearer == 'Bearer ${ProfileHarness.tokens.accessToken}') {
        return FakeReply.error(401, 'unauthorized');
      }
      final cursor = int.parse(call.options.uri.queryParameters['cursor']!);
      final token = bearer!.substring('Bearer '.length);
      (pulls[token] ??= []).add(cursor);
      if (token == otherAccess) {
        return FakeReply.json(
          200,
          SyncPullResponse(
            budgets: [
              serverPersonal(
                id: 'budget-personal-boris',
                ownerId: otherUserId,
                seq: 7,
              ),
            ],
            cursor: 7,
            hasMore: false,
          ).toJson(),
        );
      }
      return FakeReply.json(
        200,
        SyncPullResponse(cursor: cursor, hasMore: false).toJson(),
      );
    }
    if (path.endsWith('/auth/refresh')) {
      return FakeReply.error(401, 'session_expired');
    }
    if (path.endsWith('/auth/login')) {
      final body = call.json;
      if (body['password'] == wrongPassword) {
        return FakeReply.error(401, 'bad_credentials');
      }
      return body['login'] == profileUser.login
          ? signedIn(
              id: profileUserId,
              login: profileUser.login,
              access: sameAccess,
              refresh: newRefresh,
            )
          : signedIn(
              id: otherUserId,
              login: otherLogin,
              displayName: 'Борис',
              access: otherAccess,
              refresh: newRefresh,
            );
    }
    if (path.endsWith('/auth/recover')) {
      return call.json['login'] == profileUser.login
          ? signedIn(
              id: profileUserId,
              login: profileUser.login,
              access: sameAccess,
              refresh: newRefresh,
              recoveryCode: recoveryCodeText,
            )
          : signedIn(
              id: otherUserId,
              login: otherLogin,
              displayName: 'Борис',
              access: otherAccess,
              refresh: newRefresh,
              recoveryCode: recoveryCodeText,
            );
    }
    if (path.endsWith('/auth/register')) {
      return signedIn(
        id: otherUserId,
        login: otherLogin,
        displayName: 'Борис',
        access: otherAccess,
        refresh: newRefresh,
        recoveryCode: recoveryCodeText,
      );
    }
    throw StateError('unexpected ${call.method} ${call.path}');
  }
}

void testUnmounting(
  String description,
  Future<void> Function(WidgetTester tester) body,
) {
  testWidgets(description, (tester) async {
    try {
      await body(tester);
    } finally {
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}

Future<ProfileHarness> startSignedIn(
  WidgetTester tester,
  ExpiredSessionServer server, {
  int unsynced = 3,
  List<Override> overrides = const [],
}) async {
  final h = await ProfileHarness.start(
    tester,
    server: server.handle,
    overrides: [signInRequiredProvider.overrideWithValue(true), ...overrides],
    sessionEvents: true,
  );
  await tester.runAsync(() async {
    if (unsynced > 0) await addUnsyncedExpenses(h.db, unsynced);
    await (h.db.update(h.db.syncStates)..where((s) => s.id.equals(0))).write(
      const SyncStatesCompanion(cursor: Value(keptCursor)),
    );
  });
  await h.settle();
  return h;
}

Future<void> pullDownOnMonth(ProfileHarness h) async {
  final scroll = find.descendant(
    of: find.byType(RefreshIndicator),
    matching: find.byType(SingleChildScrollView),
  );
  await h.tester.fling(scroll.first, const Offset(0, 400), 1200);
  for (var i = 0; i < 10; i++) {
    await h.tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await h.tester.pump(const Duration(milliseconds: 50));
  }
  await h.settle();
}

Future<Map<String, int>> tableCounts(WidgetTester tester, AppDatabase db) async =>
    (await tester.runAsync(
      () async => {
        for (final table in const [
          'budgets',
          'categories',
          'expenses',
          'outbox',
        ])
          table: await rowsIn(db, table),
      },
    ))!;

Future<int> syncCursor(WidgetTester tester, AppDatabase db) async =>
    (await tester.runAsync(
      () => (db.select(
        db.syncStates,
      )..where((s) => s.id.equals(0))).map((s) => s.cursor).getSingle(),
    ))!;

Future<void> expireOnMonth(ProfileHarness h) async {
  await pullDownOnMonth(h);
  expect(find.byType(LoginScreen), findsOneWidget);
  expect(find.text('Сессия закончилась, войди снова'), findsOneWidget);
}

Finder authButton(String label) => find.widgetWithText(AppButton, label);

Finder dialogButton(String label) => find.descendant(
  of: find.byType(AppDialog),
  matching: find.widgetWithText(AppButton, label),
);

Future<void> submitLogin(
  ProfileHarness h, {
  required String login,
  String password = userPassword,
}) async {
  await h.enter('Логин', login);
  await h.enter('Пароль', password);
  await h.tap(authButton('Войти'));
  await h.settle();
}

Future<int> outboxSize(WidgetTester tester, AppDatabase db) async =>
    (await tester.runAsync(() => rowsIn(db, 'outbox')))!;

Future<void> submitRecover(ProfileHarness h, {required String login}) async {
  await h.tap(find.text('Забыл пароль?'));
  await h.enter('Логин', login);
  await h.enter('Код восстановления', 'k7qm-4xpa-9trb');
  await h.enter('Новый пароль', userPassword);
  await h.enter('Повтори пароль', userPassword);
  await h.tap(authButton('Сменить пароль'));
  await h.settle();
}
