import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
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
  late EngineDevice tablet;
  late String id;

  setUp(() async {
    logs = LogCapture();
    server = seededServer();
    clock = TestClock(DateTime.utc(2026, 10, 19, 15, 40));
    phone = EngineDevice(server, name: 'phone', clock: clock);
    tablet = EngineDevice(server, name: 'tablet', clock: clock);
    await phone.sync();
    id = (await phone.add(640)).id;
    expect(await phone.sync(), isA<SyncCycleDone>());
    expect(await tablet.sync(), isA<SyncCycleDone>());
    expect((await tablet.row(id))!.amountKopecks, 64000);
  });

  tearDown(() async {
    phone.dispose();
    tablet.dispose();
    await logs.dispose();
  });

  Future<void> edit(EngineDevice device, int rubles) async {
    clock.advance(const Duration(minutes: 1));
    await device.expenses.update(id, amount: Money.rubles(rubles));
  }

  int serverAmount() =>
      server.stored<Expense>(SyncEntity.expense, id).amount.kopecks;

  test('две правки одной траты: более поздняя побеждает, даже если её '
      'отправили первой; отклонённая перечитывается с сервера', () async {
    await edit(phone, 700);
    await edit(tablet, 900);

    expect(await tablet.sync(), isA<SyncCycleDone>());
    final second = await phone.sync();

    expect(second, isA<SyncCycleDone>());
    second as SyncCycleDone;
    expect(second.push.rejected.single.code, 'conflict');
    expect(serverAmount(), 90000);
    expect((await phone.row(id))!.amountKopecks, 90000);
    expect((await tablet.row(id))!.amountKopecks, 90000);
    expect(await phone.outbox.count(), 0);
    expect(
      logs.linesOf('sync', Level.WARNING),
      contains(
        contains(
          'push change rejected entity=expense id=$id code=conflict '
          'batchId=phone-batch-',
        ),
      ),
    );
    expect(
      logs.linesOf('sync', Level.INFO),
      contains(
        matches(
          RegExp(
            r'pull reason=manual re-reads from cursor=\d+ instead of stored '
            r'cursor=\d+: rejected changes come back from the server$',
          ),
        ),
      ),
    );
  });

  test(
    'две правки по порядку: более поздняя доходит до обоих телефонов',
    () async {
      await edit(phone, 700);
      expect(await phone.sync(), isA<SyncCycleDone>());
      await edit(tablet, 900);
      expect(await tablet.sync(), isA<SyncCycleDone>());
      expect(await phone.sync(), isA<SyncCycleDone>());

      expect(serverAmount(), 90000);
      expect((await phone.row(id))!.amountKopecks, 90000);
      expect((await tablet.row(id))!.amountKopecks, 90000);
    },
  );

  test('pull не затирает несинхронизированную правку новее серверной, push '
      'потом отправляет её', () async {
    await edit(phone, 700);
    expect(await phone.sync(), isA<SyncCycleDone>());
    await edit(tablet, 900);

    final pulled = await tablet.engine.pullNow(PullReason.manual);

    expect(pulled!.kept, 1);
    expect((await tablet.row(id))!.amountKopecks, 90000);
    expect(await tablet.outbox.count(), 1);
    expect(
      logs.linesOf('sync', Level.INFO),
      contains(
        contains(
          'local unsynced changes win over the server version (newer edit or '
          'pending delete) kept=expense=1 tombstonesWithServerData=-',
        ),
      ),
    );

    expect(await tablet.sync(), isA<SyncCycleDone>());
    expect(await phone.sync(), isA<SyncCycleDone>());
    expect(serverAmount(), 90000);
    expect((await phone.row(id))!.amountKopecks, 90000);
  });

  test('серверная правка новее несинхронизированной локальной: pull её '
      'применяет, локальная отклоняется', () async {
    await edit(tablet, 900);
    await edit(phone, 700);
    expect(await phone.sync(), isA<SyncCycleDone>());

    final pulled = await tablet.engine.pullNow(PullReason.manual);

    expect(pulled!.kept, 0);
    expect((await tablet.row(id))!.amountKopecks, 70000);
    final result = await tablet.sync();
    expect(result, isA<SyncCycleDone>());
    expect((result as SyncCycleDone).push.rejected.single.code, 'conflict');
    expect(serverAmount(), 70000);
    expect((await tablet.row(id))!.amountKopecks, 70000);
    expect(await tablet.outbox.count(), 0);
  });

  test('удаление против правки: удаление отправлено раньше — правка '
      'отклонена, трата удалена на обоих', () async {
    await phone.expenses.delete(id);
    clock.advance(const Duration(seconds: 6));
    await edit(tablet, 900);

    expect(await phone.sync(), isA<SyncCycleDone>());
    final result = await tablet.sync();

    expect((result as SyncCycleDone).push.rejected.single.code, 'conflict');
    expect(server.stored<Expense>(SyncEntity.expense, id).deletedAt, isNotNull);
    expect((await phone.row(id))!.deletedAt, isNotNull);
    expect((await tablet.row(id))!.deletedAt, isNotNull);
    expect(await tablet.outbox.count(), 0);
  });

  test('удаление против правки: правка отправлена раньше, но удаление всё '
      'равно побеждает', () async {
    await phone.expenses.delete(id);
    clock.advance(const Duration(seconds: 6));
    await edit(tablet, 900);

    expect(await tablet.sync(), isA<SyncCycleDone>());
    expect(serverAmount(), 90000);
    final result = await phone.sync();
    expect((result as SyncCycleDone).push.rejected, isEmpty);
    expect(await tablet.sync(), isA<SyncCycleDone>());

    expect(server.stored<Expense>(SyncEntity.expense, id).deletedAt, isNotNull);
    expect((await phone.row(id))!.deletedAt, isNotNull);
    expect((await tablet.row(id))!.deletedAt, isNotNull);
  });
}
