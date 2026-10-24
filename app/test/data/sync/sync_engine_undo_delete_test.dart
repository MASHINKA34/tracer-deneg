import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/data/db/app_database.dart';
import 'package:milionchik/data/repositories/expenses_repository.dart';
import 'package:milionchik/data/sync/pull_service.dart';
import 'package:milionchik/data/sync/sync_engine.dart';
import 'package:shared/shared.dart';

import '../api/fake_api_adapter.dart';
import 'sync_engine_fixture.dart';

void main() {
  allowSeveralPhones();

  late LogCapture logs;
  late EngineServer server;
  late TestClock clock;
  late EngineDevice phone;
  late String id;

  setUp(() async {
    logs = LogCapture();
    server = seededServer();
    clock = TestClock(DateTime.utc(2026, 10, 19, 15, 40));
    phone = EngineDevice(server, name: 'phone', clock: clock);
    await phone.sync();
    id = (await phone.add(640)).id;
    expect(await phone.sync(), isA<SyncCycleDone>());
  });

  tearDown(() async {
    phone.dispose();
    await logs.dispose();
  });

  bool deletedOnServer() =>
      server.stored<Expense>(SyncEntity.expense, id).deletedAt != null;

  test('удаление в окне «Отменить»: синхронизация его не отправляет и pull '
      'не воскрешает трату; «Отменить» — на сервер ничего не уходит', () async {
    await phone.expenses.delete(id);
    clock.advance(const Duration(seconds: 2));
    await phone.db
        .update(phone.db.syncStates)
        .write(const SyncStatesCompanion(cursor: Value(0)));

    final during = await phone.sync();

    expect((during as SyncCycleDone).push.sent, 0);
    expect(during.pull.counts.expenses, 1);
    expect(during.pull.kept, 1);
    expect(deletedOnServer(), isFalse);
    expect((await phone.row(id))!.deletedAt, isNotNull);
    expect(await phone.outbox.count(), 1);

    expect(await phone.expenses.undoDelete(id), isTrue);
    clock.advance(expenseUndoWindow);
    final after = await phone.sync();

    expect((after as SyncCycleDone).push.sent, 0);
    expect(await phone.outbox.count(), 0);
    expect(deletedOnServer(), isFalse);
    expect((await phone.row(id))!.deletedAt, isNull);
    expect(server.pushBatchIds, hasLength(1));
  });

  test('окно «Отменить» прошло: удаление уходит на сервер следующей '
      'синхронизацией', () async {
    await phone.expenses.delete(id);
    clock.advance(const Duration(seconds: 6));

    final result = await phone.sync();

    expect((result as SyncCycleDone).push.sent, 1);
    expect(deletedOnServer(), isTrue);
    expect(await phone.outbox.count(), 0);
    expect((await phone.row(id))!.deletedAt, isNotNull);
  });

  test('в окне «Отменить» другой телефон правит трату: она остаётся '
      'удалённой, а «Отменить» возвращает её с серверной правкой', () async {
    final tablet = EngineDevice(server, name: 'tablet', clock: clock);
    addTearDown(tablet.dispose);
    await tablet.sync();
    clock.advance(const Duration(seconds: 1));
    await phone.expenses.delete(id);
    clock.advance(const Duration(seconds: 1));
    await tablet.expenses.update(id, amount: Money.rubles(990));
    await tablet.sync();

    final pulled = await phone.engine.pullNow(PullReason.manual);

    expect(pulled!.kept, 1);
    final hidden = (await phone.row(id))!;
    expect(hidden.deletedAt, isNotNull);
    expect(hidden.amountKopecks, 99000);
    expect(
      logs.linesOf('sync', Level.INFO),
      contains(contains('kept=- tombstonesWithServerData=expense=1')),
    );

    expect(await phone.expenses.undoDelete(id), isTrue);
    final restored = (await phone.row(id))!;
    expect(restored.deletedAt, isNull);
    expect(restored.amountKopecks, 99000);
    clock.advance(expenseUndoWindow);
    await phone.sync();
    expect(deletedOnServer(), isFalse);
    expect(await phone.outbox.count(), 0);
  });
}
