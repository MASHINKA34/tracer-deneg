import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/data/db/app_database.dart';
import 'package:milionchik/data/repositories/prefs_repository.dart';

void main() {
  late AppDatabase db;
  late DriftPrefsRepository prefs;
  late List<LogRecord> records;
  late StreamSubscription<LogRecord> sub;

  setUp(() {
    records = [];
    Logger.root.level = Level.ALL;
    sub = Logger.root.onRecord.listen(records.add);
    db = AppDatabase.memory();
    prefs = DriftPrefsRepository(db);
  });

  tearDown(() async {
    await db.close();
    await sub.cancel();
  });

  test('строка, число и флаг сохраняются и читаются своими типами', () async {
    await prefs.setString('theme', 'dark');
    await prefs.setInt('reminderMinutes', 1260);
    await prefs.setBool('remindersEnabled', true);

    expect(await prefs.getString('theme'), 'dark');
    expect(await prefs.getInt('reminderMinutes'), 1260);
    expect(await prefs.getBool('remindersEnabled'), isTrue);

    final rows = await db.select(db.localPrefs).get();
    expect(
      {for (final r in rows) r.key: r.value},
      {'theme': 'dark', 'reminderMinutes': '1260', 'remindersEnabled': 'true'},
    );
  });

  test('нет ключа — null; повторная запись заменяет значение', () async {
    expect(await prefs.getString('theme'), isNull);
    expect(await prefs.getInt('n'), isNull);
    expect(await prefs.getBool('b'), isNull);

    await prefs.setBool('b', true);
    await prefs.setBool('b', false);
    expect(await prefs.getBool('b'), isFalse);
    expect(await db.select(db.localPrefs).get(), hasLength(1));
  });

  test('remove удаляет ключ', () async {
    await prefs.setString('theme', 'dark');
    await prefs.remove('theme');
    expect(await prefs.getString('theme'), isNull);
  });

  test('значение не того типа — null и warn без значения', () async {
    await prefs.setString('n', 'abc');
    expect(await prefs.getInt('n'), isNull);
    expect(await prefs.getBool('n'), isNull);

    final warnings = records
        .where((r) => r.loggerName == 'repo' && r.level == Level.WARNING)
        .map((r) => r.message)
        .toList();
    expect(warnings, [
      contains('key=n expected=int'),
      contains('key=n expected=bool'),
    ]);
    expect(warnings.join(), isNot(contains('abc')));
  });

  test('watch отдаёт текущее значение и каждое изменение', () async {
    final values = <int?>[];
    final sub = prefs.watchInt('n').listen(values.add);
    await pumpEventQueue();
    await prefs.setInt('n', 1);
    await pumpEventQueue();
    await prefs.setInt('n', 2);
    await pumpEventQueue();
    await prefs.remove('n');
    await pumpEventQueue();
    await sub.cancel();
    expect(values, [null, 1, 2, null]);
  });

  test('putStringIfAbsent создаёт значение один раз', () async {
    var calls = 0;
    String create() => 'v${++calls}';

    expect(await prefs.putStringIfAbsent('k', create), 'v1');
    expect(await prefs.putStringIfAbsent('k', create), 'v1');
    expect(calls, 1);
  });

  test('запись в лог — ключ и тип без значения', () async {
    await prefs.setString('theme', 'secret-looking-value');
    final debug = records
        .where((r) => r.loggerName == 'repo' && r.level == Level.FINE)
        .map((r) => r.message)
        .toList();
    expect(
      debug,
      contains(
        matches(
          RegExp(
            r'^pref set key=theme type=string length=20 '
            r'in \d+ms$',
          ),
        ),
      ),
    );
    expect(debug.join(), isNot(contains('secret-looking-value')));
  });
}
