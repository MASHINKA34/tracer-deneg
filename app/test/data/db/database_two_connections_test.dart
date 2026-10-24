import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/data/db/app_database.dart';

import '../api/fake_api_adapter.dart';

void main() {
  late Directory tmp;
  late LogCapture logs;

  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  tearDownAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false);

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('milionchik_two_conn_');
    logs = LogCapture();
  });

  tearDown(() async {
    await logs.dispose();
    tmp.deleteSync(recursive: true);
  });

  Future<AppDatabase> open() => openAppDatabase(
    directory: () async => tmp.path,
    tempDirectory: () async => tmp.path,
  );

  test('приложение и фоновая задача открыли одну базу: запись второй ждёт '
      'конца транзакции первой, а не падает с database is locked', () async {
    final app = await open();
    final background = await open();
    addTearDown(app.close);
    addTearDown(background.close);

    final inTransaction = Completer<void>();
    final backgroundWrite = background.transaction(() async {
      await background
          .into(background.localPrefs)
          .insert(LocalPrefsCompanion.insert(key: 'bg.key', value: 'x'));
      inTransaction.complete();
      await Future<void>.delayed(const Duration(milliseconds: 600));
    });
    await inTransaction.future;

    await app
        .into(app.localPrefs)
        .insert(LocalPrefsCompanion.insert(key: 'app.key', value: 'y'));
    await backgroundWrite;

    final keys = (await app.select(app.localPrefs).get()).map((p) => p.key);
    expect(keys, containsAll(['bg.key', 'app.key']));
    expect(
      logs.linesOf('db', Level.FINE),
      contains(
        contains(
          'database connection busyTimeout=5000ms journal=delete: the app '
          'and a background task open separate connections',
        ),
      ),
    );
  });
}
