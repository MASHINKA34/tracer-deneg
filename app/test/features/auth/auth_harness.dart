import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/app.dart';
import 'package:milionchik/core/auth_gate.dart';
import 'package:milionchik/core/clock.dart';
import 'package:milionchik/data/api/api_client.dart';
import 'package:milionchik/data/api/api_config.dart';
import 'package:milionchik/data/api/api_providers.dart';
import 'package:milionchik/data/db/app_database.dart';
import 'package:milionchik/data/providers.dart';
import 'package:milionchik/data/session/device_name.dart';
import 'package:milionchik/data/session/session.dart';
import 'package:milionchik/data/session/session_providers.dart';
import 'package:milionchik/data/session/session_state.dart';
import 'package:milionchik/ui/components/text_field.dart';
import 'package:shared/shared.dart';

import '../../data/api/fake_api_adapter.dart';
import '../../data/session/fake_secure_values.dart';
import '../../support/app_scope.dart';

const String testDeviceName = 'Pixel 7';

Map<String, Object?> serverUser({
  String id = 'user-server-77',
  String login = 'anya_m',
  String displayName = 'Аня',
}) => {
  'id': id,
  'login': login,
  'displayName': displayName,
  'birthdayMonth': null,
  'birthdayDay': null,
  'holidaysEnabled': true,
  'holidaysDisabled': <String>[],
  'createdAt': '2026-10-19T15:40:00.000Z',
};

FakeReply signedIn({
  int status = 200,
  String id = 'user-server-77',
  String login = 'anya_m',
  String displayName = 'Аня',
  String access = 'ACCESS-harness-kilo-lima-mike',
  String refresh = 'REFRESH-harness-november-oscar',
  String? recoveryCode,
}) => FakeReply.json(status, {
  'user': serverUser(id: id, login: login, displayName: displayName),
  'accessToken': access,
  'refreshToken': refresh,
  'recoveryCode': ?recoveryCode,
});

final class AuthHarness {
  AuthHarness._(this.tester, this.db, this.values, this.adapter, this.logs);

  final WidgetTester tester;
  final AppDatabase db;
  final FakeSecureValues values;
  final FakeApiAdapter adapter;
  final LogCapture logs;

  ProviderContainer get container =>
      ProviderScope.containerOf(tester.element(find.byType(MilionchikApp)));

  SessionState get session => container.read(sessionProvider);

  static Future<AuthHarness> start(
    WidgetTester tester, {
    required FakeHandler server,
    Session? session,
    bool signInRequired = true,
    Size size = const Size(360, 800),
    double textScale = 1,
    List<Override> overrides = const [],
  }) async {
    final logs = LogCapture();
    addTearDown(logs.dispose);
    final db = openTestDatabase();
    final values = FakeSecureValues();
    final adapter = FakeApiAdapter(server);
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = size
      ..viewPadding = const FakeViewPadding(top: 32)
      ..padding = const FakeViewPadding(top: 32);
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearAllTestValues);

    final config = ApiConfig.resolve(define: '', debugBuild: true);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          clockProvider.overrideWithValue(Clock(now: () => testNow)),
          secureValuesProvider.overrideWithValue(values),
          deviceNameProvider.overrideWithValue(testDeviceName),
          signInRequiredProvider.overrideWithValue(signInRequired),
          apiClientProvider.overrideWith(
            (ref) => ApiClient(
              config: config,
              tokens: ref.watch(tokenStoreProvider),
              adapter: adapter,
              newRequestId: () => 'ridauthscreen001',
            ),
          ),
          if (session != null)
            sessionProvider.overrideWithBuild(
              (ref, _) => SessionActive(session.user),
            ),
          ...overrides,
        ],
        child: MilionchikApp(today: LocalDate.fromDateTime(testNow)),
      ),
    );
    await tester.pumpAndSettle();
    return AuthHarness._(tester, db, values, adapter, logs);
  }

  Finder field(String label) =>
      find.ancestor(of: find.text(label), matching: find.byType(AppTextField));

  Finder input(String label) =>
      find.descendant(of: field(label), matching: find.byType(TextField));

  Future<void> enter(String label, String text) async {
    await tester.enterText(input(label), text);
    await tester.pump();
  }

  String? errorUnder(String label) =>
      tester.widget<AppTextField>(field(label)).errorText;

  bool obscured(String label) =>
      tester.widget<TextField>(input(label)).obscureText;

  Future<void> tapText(String text) async {
    final target = find.text(text).last;
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Future<void> tapLabel(String label) async {
    final target = find.bySemanticsLabel(label).last;
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  List<String> linesOf(String logger, [Level from = Level.ALL]) =>
      logs.linesOf(logger, from);
}
