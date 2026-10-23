import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/app.dart';
import 'package:milionchik/core/auth_gate.dart';
import 'package:milionchik/core/data_startup.dart';
import 'package:milionchik/data/api/token_store.dart';
import 'package:milionchik/data/db/app_database.dart';
import 'package:milionchik/data/dev_seed.dart';
import 'package:milionchik/data/repositories/prefs_repository.dart';
import 'package:milionchik/data/session/session.dart';
import 'package:milionchik/features/auth/login_screen.dart';
import 'package:milionchik/features/month/month_screen.dart';

import '../data/api/fake_api_adapter.dart';

const _session = Session(
  user: SessionUser(
    userId: 'user-server-9',
    login: 'seed_login',
    displayName: 'Сид',
  ),
  tokens: AuthTokens(
    accessToken: 'ACCESS-seed-gate-echo-foxtrot',
    refreshToken: 'REFRESH-seed-gate-golf-hotel',
  ),
);

void main() {
  late LogCapture logs;
  late int seedCalls;

  setUpAll(() => initializeDateFormatting('ru'));

  setUp(() {
    logs = LogCapture();
    seedCalls = 0;
  });

  tearDown(() => logs.dispose());

  Future<DevSeedResult> countingSeed(AppDatabase db) async {
    seedCalls++;
    return const DevSeedResult(DevSeedStatus.seeded, budgets: 1);
  }

  Future<DataReady> start(
    AppDatabase db, {
    Session? session,
    String flag = 'true',
  }) async => await startData(
    open: () async => db,
    seed: countingSeed,
    readSession: () async => session,
    devSeedFlag: flag,
  ) as DataReady;

  test(
    'DEV_SEED=true, сессии нет и вход не выполнялся - сид запускается',
    () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);

      final data = await start(db);

      expect(seedCalls, 1);
      expect(data.seed.status, DevSeedStatus.seeded);
      expect(data.devSeedDemo, isTrue);
      expect(logs.linesOf('seed', Level.WARNING), isEmpty);
    },
  );

  test('DEV_SEED=true при сохранённой сессии - сид не запускается, warn '
      '[seed] с причиной, вход как обычно', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);

    final data = await start(db, session: _session);

    expect(seedCalls, 0);
    expect(data.seed.status, DevSeedStatus.ignored);
    expect(data.devSeedDemo, isFalse);
    expect(logs.linesOf('seed', Level.WARNING), [
      endsWith(
        'DEV_SEED=true ignored: signed in (session userId=user-server-9) → '
        'no demo data, account data and sign-in work as usual',
      ),
    ]);
    expect(logs.text, isNot(contains('seed_login')));
    expect(logs.text, isNot(contains(_session.tokens.accessToken)));
  });

  test('DEV_SEED=true, сессии нет, но на телефоне уже входили - сид не '
      'запускается', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    await DriftPrefsRepository(db).setBool(PrefKeys.signedInBefore, true);

    final data = await start(db);

    expect(seedCalls, 0);
    expect(data.seed.status, DevSeedStatus.ignored);
    expect(data.devSeedDemo, isFalse);
    expect(logs.linesOf('seed', Level.WARNING), [
      endsWith(
        'DEV_SEED=true ignored: this phone signed in before (signedInBefore) '
        '→ no demo data, sign-in screen as usual',
      ),
    ]);
  });

  test(
    'без DEV_SEED проверка входа не делается и в [seed] не пишется',
    () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);

      final data = await start(db, session: _session, flag: '');

      expect(seedCalls, 1);
      expect(logs.linesOf('seed'), isEmpty);
      expect(data.session, same(_session));
    },
  );

  Future<void> mount(WidgetTester tester, DataReady data) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(360, 800);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(appRoot(data));
    await tester.pumpAndSettle();
  }

  Future<void> unmount(WidgetTester tester, AppDatabase db) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
    await tester.runAsync(db.close);
  }

  testWidgets('appRoot без сессии и без DEV_SEED: вход обязателен, первым '
      'экран входа', (tester) async {
    final db = AppDatabase.memory();
    await mount(tester, DataReady(db, const DevSeedResult(DevSeedStatus.off)));

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(MonthScreen), findsNothing);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MilionchikApp)),
    );
    expect(container.read(signInRequiredProvider), isTrue);
    expect(
      logs.linesOf('auth', Level.INFO),
      contains(
        endsWith(
          'sign-in gate: session=absent devSeed=off → sign-in screen when '
          'there is no session',
        ),
      ),
    );

    await unmount(tester, db);
  });

  testWidgets('appRoot с демо-данными DEV_SEED (засеяно или уже было): '
      'главная без входа', (tester) async {
    for (final status in [DevSeedStatus.seeded, DevSeedStatus.skipped]) {
      final db = AppDatabase.memory();
      await mount(tester, DataReady(db, DevSeedResult(status)));

      expect(find.byType(MonthScreen), findsOneWidget, reason: status.name);
      expect(find.byType(LoginScreen), findsNothing, reason: status.name);

      await unmount(tester, db);
    }
    expect(
      logs.linesOf('auth', Level.INFO),
      contains(
        endsWith(
          'sign-in gate: session=absent devSeed=skipped → DEV_SEED demo, app '
          'opens without sign-in',
        ),
      ),
    );
  });

  testWidgets('appRoot: DEV_SEED проигнорирован из-за входа - экран входа', (
    tester,
  ) async {
    final db = AppDatabase.memory();
    await mount(
      tester,
      DataReady(db, const DevSeedResult(DevSeedStatus.ignored)),
    );

    expect(find.byType(LoginScreen), findsOneWidget);

    await unmount(tester, db);
  });
}
