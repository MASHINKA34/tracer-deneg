import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/data/db/app_database.dart';

void main() {
  late Directory tmp;
  late List<LogRecord> records;
  late StreamSubscription<LogRecord> sub;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('milionchik_db_');
    records = [];
    Logger.root.level = Level.ALL;
    sub = Logger.root.onRecord.listen(records.add);
  });

  tearDown(() async {
    await sub.cancel();
    tmp.deleteSync(recursive: true);
  });

  Future<AppDatabase> open(String dir) => openAppDatabase(
    directory: () async => dir,
    tempDirectory: () async => tmp.path,
  );

  List<String> messages(Level level) => [
    for (final r in records)
      if (r.loggerName == 'db' && r.level == level) r.message,
  ];

  test('файл базы создаётся и открывается повторно без пересоздания', () async {
    final path = '${tmp.path}/$databaseFileName';

    final first = await open(tmp.path);
    await first
        .into(first.localPrefs)
        .insert(LocalPrefsCompanion.insert(key: 'theme', value: 'dark'));
    await first.close();

    expect(File(path).existsSync(), isTrue);
    final opened = messages(Level.INFO)
        .where((m) => m.startsWith('database opened'))
        .toList();
    expect(opened, hasLength(1));
    expect(
      opened.single,
      matches(
        RegExp(
          '^database opened path=${RegExp.escape(path)} schema=1 '
          r'created=true sqlite=3\.\d+\.\d+ in \d+ms$',
        ),
      ),
    );
    expect(messages(Level.INFO), contains(startsWith('schema created')));

    records.clear();
    final second = await open(tmp.path);
    final prefs = await second.select(second.localPrefs).get();
    await second.close();

    expect(prefs.map((p) => p.value), ['dark']);
    expect(messages(Level.INFO), [
      'opening database path=$path',
      matches(RegExp(r'schema=1 created=false sqlite=\S+ in \d+ms$')),
    ]);
  });

  test('файл не база — error с путём, типом и стеком', () async {
    final path = '${tmp.path}/$databaseFileName';
    File(path).writeAsStringSync('not a database ' * 100);

    await expectLater(open(tmp.path), throwsA(anything));

    final errors = records
        .where((r) => r.loggerName == 'db' && r.level == Level.SEVERE)
        .toList();
    expect(errors, hasLength(1));
    final error = errors.single;
    expect(error.message, startsWith('database open failed path=$path after '));
    expect(error.message, contains('SqliteException'));
    expect(error.error, isNotNull);
    expect(error.stackTrace, isNotNull);
  });
}
