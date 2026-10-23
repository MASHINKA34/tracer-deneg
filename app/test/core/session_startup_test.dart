import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/app.dart';
import 'package:milionchik/core/data_startup.dart';
import 'package:milionchik/data/api/token_store.dart';
import 'package:milionchik/data/current_user.dart';
import 'package:milionchik/data/db/app_database.dart';
import 'package:milionchik/data/dev_seed.dart';
import 'package:milionchik/data/providers.dart';
import 'package:milionchik/data/session/session.dart';
import 'package:milionchik/data/session/session_providers.dart';
import 'package:milionchik/data/session/session_state.dart';
import 'package:shared/shared.dart';

const _session = Session(
  user: SessionUser(
    userId: 'user-server-5',
    login: 'lisa_login',
    displayName: 'Лиса',
  ),
  tokens: AuthTokens(
    accessToken: 'ACCESS-bravo-alpha-zulu-yankee',
    refreshToken: 'REFRESH-delta-charlie-xray-whiskey',
  ),
);

Future<DevSeedResult> _noSeed(AppDatabase db) async =>
    const DevSeedResult(DevSeedStatus.off);

void main() {
  late List<LogRecord> records;
  late StreamSubscription<LogRecord> sub;

  setUpAll(() => initializeDateFormatting('ru'));

  setUp(() {
    records = [];
    Logger.root.level = Level.ALL;
    sub = Logger.root.onRecord.listen(records.add);
  });

  tearDown(() => sub.cancel());

  List<String> lines(String logger, [Level level = Level.ALL]) => [
    for (final r in records)
      if (r.loggerName == logger && r.level >= level) formatLogRecord(r),
  ];

  test('старт: сессия читается из хранилища и попадает в DataReady', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);

    final data = await startData(
      open: () async => db,
      seed: _noSeed,
      readSession: () async => _session,
    );

    expect((data as DataReady).session, same(_session));
  });

  test('старт: чтение сессии упало - приложение стартует без сессии, warn '
      'с типом', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);

    final data = await startData(
      open: () async => db,
      seed: _noSeed,
      readSession: () async => throw StateError('keystore gone'),
    );

    expect(data, isA<DataReady>());
    expect((data as DataReady).session, isNull);
    final warning = lines('session', Level.WARNING).single;
    expect(warning, contains('session restore failed after '));
    expect(
      warning,
      contains(
        '→ starting without session: StateError: Bad state: keystore '
        'gone',
      ),
    );
  });

  Future<ProviderContainer> mount(
    WidgetTester tester,
    AppDatabase db,
    Session? session,
  ) async {
    tester.view
      ..devicePixelRatio = 2
      ..physicalSize = const Size(360, 800) * 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      appRoot(
        DataReady(db, const DevSeedResult(DevSeedStatus.off), session: session),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 10));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    }
    return ProviderScope.containerOf(
      tester.element(find.byType(MilionchikApp)),
    );
  }

  Future<void> unmount(WidgetTester tester, AppDatabase db) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
    await tester.runAsync(db.close);
  }

  testWidgets('appRoot с восстановленной сессией: состояние «есть», '
      'CurrentUser - userId из сессии', (tester) async {
    final db = AppDatabase.memory();
    final container = await mount(tester, db, _session);

    expect(container.read(sessionProvider), isA<SessionActive>());
    expect(container.read(sessionProvider).user, _session.user);
    expect(container.read(currentUserProvider), isA<SessionCurrentUser>());
    expect(await container.read(currentUserProvider).userId(), 'user-server-5');
    expect(
      lines('session', Level.INFO),
      contains(endsWith('current user from session userId=user-server-5')),
    );

    await unmount(tester, db);
  });

  testWidgets('appRoot без сессии: состояние «нет», CurrentUser - локальный', (
    tester,
  ) async {
    final db = AppDatabase.memory();
    final container = await mount(tester, db, null);

    expect(container.read(sessionProvider), isA<SessionAbsent>());
    expect(container.read(currentUserProvider), isA<LocalPrefsCurrentUser>());

    await unmount(tester, db);
  });
}
