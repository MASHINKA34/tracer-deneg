import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/data/current_user.dart';
import 'package:milionchik/data/db/app_database.dart';
import 'package:milionchik/data/repositories/prefs_repository.dart';
import 'package:shared/shared.dart';

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

  test(
    'id создаётся при первом обращении и сохраняется в local_prefs',
    () async {
      final user = LocalPrefsCurrentUser(prefs);
      final id = await user.userId();

      expect(isUuid(id), isTrue);
      expect(await prefs.getString(PrefKeys.localUserId), id);
      expect(await user.userId(), id);
      expect(
        records
            .where((r) => r.loggerName == 'repo' && r.level == Level.INFO)
            .map((r) => r.message),
        [startsWith('local user id created userId=$id key=localUserId in ')],
      );
    },
  );

  test('новый экземпляр берёт сохранённый id, а не создаёт новый', () async {
    final first = await LocalPrefsCurrentUser(prefs).userId();
    final second = await LocalPrefsCurrentUser(prefs).userId();
    expect(second, first);
    expect(
      records.where((r) => r.message.startsWith('local user id created')),
      hasLength(1),
    );
  });

  test('одновременные обращения получают один id', () async {
    var created = 0;
    final user = LocalPrefsCurrentUser(prefs, newId: () => 'user-${++created}');
    final ids = await Future.wait([user.userId(), user.userId()]);
    expect(ids, ['user-1', 'user-1']);
    expect(created, 1);
  });
}
