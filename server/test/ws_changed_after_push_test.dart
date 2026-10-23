import 'dart:async';

import 'package:server/auth/auth_middleware.dart';
import 'package:server/sync/sync_notifier.dart';
import 'package:server/ws/ws_hub.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/budget_support.dart';
import 'support/push_support.dart';
import 'support/shared_budget_support.dart';
import 'support/sync_support.dart';
import 'support/test_support.dart';
import 'support/ws_support.dart';

const _secretComment = 'подарок-сюрприз-для-бориса';
const _secretKopecks = 98765432;

void main() {
  late LogCapture logs;
  late WsHarness ws;
  late TestUser anna;
  late TestUser boris;
  late TestUser chris;
  late String family;
  late String annaPersonal;

  setUp(() async {
    logs = LogCapture();
    ws = await WsHarness.start();
    anna = await registerTestUser(ws.api, 'ws.anna');
    boris = await registerTestUser(ws.api, 'ws.boris');
    chris = await registerTestUser(ws.api, 'ws.chris');
    family = (await createSharedBudget(ws.api, anna)).id;
    await joinBudget(ws.api, boris, await inviteCodeFor(ws.api, anna, family));
    annaPersonal = await SharedBudgetFixture(ws.api).personalBudgetOf(anna.id);
  });

  Future<SyncChange> expenseIn(String budgetId, TestUser author) async =>
      SyncChange.upsert(
        expenseRecord(
          budgetId: budgetId,
          categoryId: await firstCategoryOf(ws.api, budgetId),
          authorId: author.id,
          kopecks: _secretKopecks,
          comment: _secretComment,
        ),
      );

  group('changed после push', () {
    test('второй участник бюджета получает changed меньше чем за 1 с, '
        'чужой — нет', () async {
      final borisCursor = (await pullUntilDone(ws.api, boris)).cursor;
      final annaWs = await ws.connect(anna);
      final borisWs = await ws.connect(boris);
      final chrisWs = await ws.connect(chris);
      final change = await expenseIn(family, anna);

      final sw = Stopwatch()..start();
      final pushed = await pushAs(ws.api, anna, [change]);
      final message = await borisWs.next(
        'changed',
        timeout: const Duration(seconds: 1),
      );
      final elapsed = sw.elapsedMilliseconds;
      print('changed reached boris ${elapsed}ms after push started');

      expect(elapsed, lessThan(1000));
      expect(message, {
        'type': 'changed',
        'budgetIds': [family],
        'cursor': pushed.cursor,
      });
      expect(await annaWs.next('changed'), message);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(chrisWs.messages, isEmpty);
      expect(borisWs.ofType('changed'), hasLength(1));

      final pulled = await pullUntilDone(ws.api, boris, cursor: borisCursor);
      expect(pulled.all((p) => p.expenses).map((e) => e.id), [change.id]);
      expect(pulled.cursor, pushed.cursor);
    });

    test('budgetIds — только бюджеты получателя: личный бюджет автора '
        'не виден второму участнику', () async {
      final annaWs = await ws.connect(anna);
      final borisWs = await ws.connect(boris);

      final pushed = await pushAs(ws.api, anna, [
        await expenseIn(family, anna),
        await expenseIn(annaPersonal, anna),
      ]);

      final toAnna = await annaWs.next('changed');
      final toBoris = await borisWs.next('changed');
      expect(toAnna['budgetIds'], [family, annaPersonal]..sort());
      expect(toBoris['budgetIds'], [family]);
      expect(toAnna['cursor'], pushed.cursor);
      expect(toBoris['cursor'], pushed.cursor);
    });

    test('push только в личный бюджет — второму участнику ничего', () async {
      final annaWs = await ws.connect(anna);
      final borisWs = await ws.connect(boris);

      await pushAs(ws.api, anna, [await expenseIn(annaPersonal, anna)]);

      expect((await annaWs.next('changed'))['budgetIds'], [annaPersonal]);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(borisWs.messages, isEmpty);
    });

    test('ничего не записано (отказ по правам) — changed никому', () async {
      final annaWs = await ws.connect(anna);
      final borisWs = await ws.connect(boris);
      final chrisPersonal = await SharedBudgetFixture(ws.api)
          .personalBudgetOf(chris.id);

      final pushed = await pushAs(ws.api, anna, [
        SyncChange.upsert(
          expenseRecord(
            budgetId: chrisPersonal,
            categoryId: await firstCategoryOf(ws.api, chrisPersonal),
            authorId: anna.id,
          ),
        ),
      ]);

      expect(pushed.applied, isEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(annaWs.messages, isEmpty);
      expect(borisWs.messages, isEmpty);
    });

    test('все устройства участников получают changed; рассылка в логе '
        'на debug с budgetIds и числом получателей', () async {
      final annaPhone = await ws.connect(anna);
      final annaTablet = await ws.connect(anna);
      final borisWs = await ws.connect(boris);

      final pushed = await pushAs(ws.api, anna, [
        await expenseIn(family, anna),
      ]);

      for (final client in [annaPhone, annaTablet, borisWs]) {
        expect((await client.next('changed'))['cursor'], pushed.cursor);
      }
      await waitUntil(
        () => logs.lines.any((l) => l.contains('ws changed broadcast')),
      );
      final line = logs.lines.singleWhere(
        (l) => l.contains('ws changed broadcast'),
      );
      expect(line, contains('DEBUG'));
      expect(line, contains('[ws]'));
      expect(line, contains('reason=push'));
      expect(line, contains('budgetIds=[$family]'));
      expect(line, contains('cursor=${pushed.cursor}'));
      expect(line, contains('users=2 recipients=3 failed=0'));
      expect(logs.text, isNot(contains(_secretComment)));
      expect(logs.text, isNot(contains('$_secretKopecks')));
    });

    test(
      'ошибка отправки одному подключению — warn, остальные получают',
      () async {
        final borisWs = await ws.connect(boris);
        final incoming = StreamController<Object?>();
        addTearDown(incoming.close);
        ws.hub.accept(
          AuthContext(
            userId: anna.id,
            sessionId: newId(),
            expiresAt: DateTime.now().add(const Duration(minutes: 15)),
          ),
          WsPeer(
            messages: incoming.stream,
            send: (_) => throw StateError('socket already gone'),
            close: (code, reason) async {},
            remoteCloseCode: () => null,
            remoteCloseReason: () => null,
          ),
        );

        ws.hub.budgetsChanged(
          BudgetsChanged(
            reason: 'push',
            userId: anna.id,
            budgetIds: {family},
            cursor: 4242,
          ),
        );

        expect((await borisWs.next('changed'))['cursor'], 4242);
        await waitUntil(
          () => logs.lines.any((l) => l.contains('ws changed broadcast')),
        );
        final warning = logs.lines.singleWhere(
          (l) => l.contains('ws send failed'),
        );
        expect(warning, contains('WARN'));
        expect(warning, contains('type=changed'));
        expect(warning, contains('userId=${anna.id}'));
        expect(warning, contains('socket already gone'));
        expect(logs.text, contains('users=2 recipients=1 failed=1'));
      },
    );
  });
}
