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
    tmp = Directory.systemTemp.createTempSync('milionchik_open_busy_');
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

  test('фоновая задача коммитит (EXCLUSIVE), а приложение в этот момент '
      'открывает базу: открытие ждёт и проходит, а не падает locked', () async {
    final background = await open();
    addTearDown(background.close);
    await background.customStatement('BEGIN EXCLUSIVE');
    final commit = Future<void>.delayed(
      const Duration(milliseconds: 800),
      () => background.customStatement('COMMIT'),
    );

    final sw = Stopwatch()..start();
    final app = await open();
    sw.stop();
    addTearDown(app.close);
    await commit;

    final prefs = await app.select(app.localPrefs).get();
    expect(prefs, isEmpty);
    expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(500));
    expect(logs.linesOf('db', Level.SEVERE), isEmpty);
    expect(
      logs.linesOf('db', Level.FINE),
      contains(
        matches(
          RegExp(
            r'database connection busyTimeout=5000ms journal=delete set '
            r'before the first query, open took \d+ms',
          ),
        ),
      ),
    );
  });
}
