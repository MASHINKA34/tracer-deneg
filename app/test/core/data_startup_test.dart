import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show TableOrViewStatements;
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/app.dart';
import 'package:milionchik/core/data_startup.dart';
import 'package:milionchik/data/db/app_database.dart';
import 'package:milionchik/data/dev_seed.dart';
import 'package:milionchik/data/providers.dart';
import 'package:milionchik/features/month/month_screen.dart';
import 'package:milionchik/features/startup/database_error_app.dart';
import 'package:milionchik/ui/components/logo.dart';
import 'package:shared/shared.dart';

void main() {
  late List<LogRecord> records;
  late StreamSubscription<LogRecord> sub;

  setUp(() {
    records = [];
    Logger.root.level = Level.ALL;
    sub = Logger.root.onRecord.listen(records.add);
  });

  tearDown(() => sub.cancel());

  List<String> appLines([Level level = Level.ALL]) => [
    for (final r in records)
      if (r.loggerName == 'app' && r.level >= level) formatLogRecord(r),
  ];

  test('шаг старта: база открыта, затем dev seed — две строки [app] с мс '
      'по порядку', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    final calls = <String>[];

    final data = await startData(
      open: () async {
        calls.add('open');
        return db;
      },
      seed: (opened) async {
        calls.add('seed');
        expect(opened, same(db));
        return const DevSeedResult(
          DevSeedStatus.seeded,
          budgets: 1,
          categories: 11,
          expenses: 57,
        );
      },
    );

    expect(calls, ['open', 'seed']);
    expect(data, isA<DataReady>());
    expect((data as DataReady).db, same(db));
    expect(data.seed.status, DevSeedStatus.seeded);
    expect(appLines(), [
      matches(RegExp(r'INFO  \[app\] database opened in \d+ms$')),
      matches(
        RegExp(
          r'INFO  \[app\] dev seed done in \d+ms budgets=1 categories=11 '
          r'expenses=57$',
        ),
      ),
    ]);
  });

  test('без --dart-define=DEV_SEED настоящий сид выключен: база пустая, '
      'в логе «dev seed off»', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);

    final data = await startData(open: () async => db);

    expect((data as DataReady).seed.status, DevSeedStatus.off);
    expect(await db.budgets.count().getSingle(), 0);
    expect(await db.expenses.count().getSingle(), 0);
    expect(
      appLines().last,
      matches(
        RegExp(r'INFO  \[app\] dev seed off in \d+ms: DEV_SEED not set$'),
      ),
    );
  });

  test('файл базы испорчен — экран ошибки вместо падения: error [app] с '
      'типом, кодом и стеком, сид не запускается', () async {
    final tmp = Directory.systemTemp.createTempSync('milionchik_start_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    File('${tmp.path}/$databaseFileName')
        .writeAsStringSync('not a database ' * 100);
    var seeded = false;

    final data = await startData(
      open: () => openAppDatabase(
        directory: () async => tmp.path,
        tempDirectory: () async => tmp.path,
      ),
      seed: (_) async {
        seeded = true;
        return const DevSeedResult(DevSeedStatus.off);
      },
    );

    expect(data, isA<DataUnavailable>());
    expect(seeded, isFalse);
    final errors = appLines(Level.SEVERE);
    expect(errors, hasLength(1));
    expect(
      errors.single,
      matches(
        RegExp(
          r'ERROR \[app\] database open failed after \d+ms, showing database '
          r'error screen instead of the app: SqliteException: SqliteException\(26\)',
        ),
      ),
    );
    expect(errors.single, contains('file is not a database'));
    expect(errors.single, contains('stack:'));
    expect(appLines().where((l) => l.contains('database opened')), isEmpty);
  });

  test('ошибка открытия со значениями параметров SQL — в логе [app] '
      'только их типы', () async {
    final data = await startData(
      open: () async => throw SqliteException(
        extendedResultCode: 11,
        message: 'database disk image is malformed',
        causingStatement: 'SELECT value FROM local_prefs WHERE key = ?',
        parametersToStatement: ['secret-key-value'],
      ),
    );

    expect(data, isA<DataUnavailable>());
    final line = appLines(Level.SEVERE).single;
    expect(line, contains('database disk image is malformed'));
    expect(line, contains('SELECT value FROM local_prefs WHERE key = ?'));
    expect(line, contains('<text:16>'));
    expect(line, isNot(contains('secret-key-value')));
  });

  test('сид упал исключением — приложение всё равно стартует с базой, '
      'error и warn в [app]', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);

    final data = await startData(
      open: () async => db,
      seed: (_) async => throw StateError('seed exploded'),
    );

    expect((data as DataReady).seed.status, DevSeedStatus.failed);
    expect(appLines(Level.WARNING), [
      matches(
        RegExp(
          r'ERROR \[app\] dev seed crashed after \d+ms, starting without '
          r'demo data: StateError: Bad state: seed exploded',
        ),
      ),
      matches(
        RegExp(
          r'WARN  \[app\] dev seed failed in \d+ms, starting without demo '
          r'data: error in \[seed\] above$',
        ),
      ),
    ]);
  });

  testWidgets('база открыта — MilionchikApp внутри ProviderScope с этой '
      'базой', (tester) async {
    final db = AppDatabase.memory();

    await tester.pumpWidget(
      appRoot(DataReady(db, const DevSeedResult(DevSeedStatus.off))),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ProviderScope), findsOneWidget);
    expect(find.byType(MilionchikApp), findsOneWidget);
    expect(find.byType(MonthScreen), findsOneWidget);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MilionchikApp)),
    );
    expect(container.read(appDatabaseProvider), same(db));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
    await db.close();
  });

  testWidgets('база не открылась — экран-заглушка с текстом из ARB, без '
      'MilionchikApp', (tester) async {
    await tester.pumpWidget(appRoot(const DataUnavailable('broken')));
    await tester.pumpAndSettle();

    expect(find.byType(DatabaseErrorScreen), findsOneWidget);
    expect(find.byType(MilionchikApp), findsNothing);
    expect(find.text('Не удалось открыть траты'), findsOneWidget);
    expect(
      find.text(
        'Закройте «Милиончик» и откройте снова. Если ошибка повторится, '
        'напишите разработчику.',
      ),
      findsOneWidget,
    );
    expect(find.byType(AppLogo), findsOneWidget);
  });
}
