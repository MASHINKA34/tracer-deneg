import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/budget_support.dart';
import 'support/shared_budget_support.dart';
import 'support/sync_support.dart';
import 'support/test_support.dart';
import 'support/ws_support.dart';

void main() {
  late LogCapture logs;
  late WsHarness ws;
  late TestUser anna;
  late TestUser boris;
  late TestUser chris;
  late String family;

  setUp(() async {
    logs = LogCapture();
    ws = await WsHarness.start();
    anna = await registerTestUser(ws.api, 'ws.anna');
    boris = await registerTestUser(ws.api, 'ws.boris');
    chris = await registerTestUser(ws.api, 'ws.chris');
    family = (await createSharedBudget(ws.api, anna)).id;
    await joinBudget(ws.api, boris, await inviteCodeFor(ws.api, anna, family));
  });

  Future<void> expectSilence(List<WsTestClient> clients) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    for (final client in clients) {
      expect(client.messages, isEmpty);
    }
  }

  Future<SyncPullResponse> pullFrom(TestUser user, int cursor) async {
    final pulled = await pullUntilDone(ws.api, user, cursor: cursor);
    return pulled.pages.last;
  }

  group('changed после операций с бюджетами', () {
    test('исключённый получает changed и по pull — removedBudgetIds', () async {
      final borisCursor = (await pullUntilDone(ws.api, boris)).cursor;
      final annaWs = await ws.connect(anna);
      final borisWs = await ws.connect(boris);
      final chrisWs = await ws.connect(chris);

      final removed = await removeMemberRaw(ws.api, anna, family, boris.id);
      expect(removed.status, 204);

      final message = await borisWs.next('changed');
      expect(message['budgetIds'], [family]);
      expect(await annaWs.next('changed'), message);
      final pulled = await pullFrom(boris, borisCursor);
      expect(pulled.removedBudgetIds, [family]);
      expect(pulled.cursor, message['cursor']);
      expect(
        message['cursor'],
        (await memberRow(ws.api, family, boris.id))!.seq,
      );
      await expectSilence([chrisWs]);
      expect(logs.text, contains('reason=budget_remove_member'));
    });

    test('вышедший участник (другое устройство) и создатель получают '
        'changed', () async {
      final borisCursor = (await pullUntilDone(ws.api, boris)).cursor;
      final annaWs = await ws.connect(anna);
      final borisTablet = await ws.connect(boris);
      final chrisWs = await ws.connect(chris);

      final left = await leaveRaw(ws.api, boris, family);
      expect(left.status, 204);

      final message = await borisTablet.next('changed');
      expect(message['budgetIds'], [family]);
      expect(await annaWs.next('changed'), message);
      final pulled = await pullFrom(boris, borisCursor);
      expect(pulled.removedBudgetIds, [family]);
      expect(pulled.cursor, message['cursor']);
      await expectSilence([chrisWs]);
    });

    test('удаление бюджета: участники получают changed, pull приносит '
        'removedBudgetIds', () async {
      final borisCursor = (await pullUntilDone(ws.api, boris)).cursor;
      final annaWs = await ws.connect(anna);
      final borisWs = await ws.connect(boris);
      final chrisWs = await ws.connect(chris);

      final deleted = await deleteBudgetRaw(ws.api, anna, family);
      expect(deleted.status, 204);

      final message = await borisWs.next('changed');
      expect(message['budgetIds'], [family]);
      expect(await annaWs.next('changed'), message);
      final pulled = await pullFrom(boris, borisCursor);
      expect(pulled.removedBudgetIds, [family]);
      expect(pulled.cursor, lessThanOrEqualTo(message['cursor']! as int));
      final after = await pullFrom(boris, message['cursor']! as int);
      expect(after.removedBudgetIds, isEmpty);
      expect(after.totalCount, 0);
      await expectSilence([chrisWs]);
    });

    test('вступление по коду: участники бюджета получают changed', () async {
      final annaCursor = (await pullUntilDone(ws.api, anna)).cursor;
      final annaWs = await ws.connect(anna);
      final borisWs = await ws.connect(boris);
      final chrisWs = await ws.connect(chris);
      final code = await inviteCodeFor(ws.api, anna, family);
      await expectSilence([annaWs, borisWs, chrisWs]);

      await joinBudget(ws.api, chris, code);

      final message = await annaWs.next('changed');
      expect(message['budgetIds'], [family]);
      expect(await borisWs.next('changed'), message);
      expect(await chrisWs.next('changed'), message);
      final pulled = await pullFrom(anna, annaCursor);
      expect(pulled.cursor, message['cursor']);
      expect(
        (await pullUntilDone(
          ws.api,
          anna,
          cursor: annaCursor,
        )).all((p) => p.members).map((m) => m.userId),
        contains(chris.id),
      );
    });

    test('повторный вход уже вступившего — ничего не записано, '
        'changed нет', () async {
      final code = await inviteCodeFor(ws.api, anna, family);
      final annaWs = await ws.connect(anna);
      final borisWs = await ws.connect(boris);

      await joinBudget(ws.api, boris, code);

      await expectSilence([annaWs, borisWs]);
    });

    test('создание общего бюджета: changed только создателю', () async {
      final annaCursor = (await pullUntilDone(ws.api, anna)).cursor;
      final annaWs = await ws.connect(anna);
      final borisWs = await ws.connect(boris);

      final created = await createSharedBudget(ws.api, anna, name: 'Отпуск');

      final message = await annaWs.next('changed');
      expect(message['budgetIds'], [created.id]);
      expect(message['cursor'], greaterThan(created.seq!));
      expect((await pullFrom(anna, annaCursor)).cursor, message['cursor']);
      await expectSilence([borisWs]);
      expect(logs.text, contains('reason=budget_create'));
    });
  });
}
