import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/data/sync/sync_engine.dart';
import 'package:milionchik/features/month/month_header.dart';
import 'package:milionchik/ui/components/sync_status.dart';
import 'package:milionchik/ui/icons/app_icon.dart';

import '../auth/session_expired_fixture.dart' show testUnmounting;
import '../profile/sign_out_fixture.dart' show addUnsyncedExpenses;
import '../recurring/recurring_fixture.dart' show writeWhileShown;
import 'sync_status_fixture.dart';

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testUnmounting('нет сети: 3 траты → «Ждёт сети · 3» и облако с чертой, '
      'новая трата сразу в числе; сеть есть → «Синхронизировано»', (
    tester,
  ) async {
    final server = SyncStatusServer()..mode = ServerMode.offline;
    final h = await startMonth(tester, server);
    expect(headerSync('Синхронизировано'), findsOneWidget);
    expect(headerIcon(AppIcons.cloudCheck), findsOneWidget);

    await writeWhileShown(tester, () => addUnsyncedExpenses(h.db, 3));
    final offline = await syncAndWait(h, SyncReason.outbox);

    expect(offline, isA<SyncCycleFailed>());
    expect(headerSync('Ждёт сети · 3'), findsOneWidget);
    expect(headerIcon(AppIcons.cloudOff), findsOneWidget);
    expect(headerIcon(AppIcons.cloudCheck), findsNothing);

    await writeWhileShown(tester, () => addUnsyncedExpenses(h.db, 1));
    expect(headerSync('Ждёт сети · 4'), findsOneWidget);

    server.mode = ServerMode.online;
    final online = await syncAndWait(h, SyncReason.network);

    expect(online, isA<SyncCycleDone>());
    expect((online as SyncCycleDone).push.applied, 4);
    expect(headerSync('Синхронизировано'), findsOneWidget);
    expect(headerIcon(AppIcons.cloudCheck), findsOneWidget);
    expect(headerIcon(AppIcons.cloudOff), findsNothing);
    final sync = h.linesOf('sync', Level.FINE);
    expect(
      sync,
      containsAllInOrder([
        contains('sync status shown done → done queue=0→3 phase=idle'),
        contains('sync status shown done → sending queue=3→3 phase=sending'),
        contains(
          'sync status shown sending → waiting queue=3→3 '
          'phase=waitingNetwork',
        ),
        contains('sync status shown waiting → waiting queue=3→4'),
        contains('sync status shown waiting → sending queue=4→4'),
        contains('sync status shown sending → done queue=0→0 phase=idle'),
      ]),
    );
    expect(
      h.linesOf('month', Level.FINE),
      containsAllInOrder([
        contains('header sync indicator done → sending'),
        contains('header sync indicator sending → waiting'),
        contains('header sync indicator waiting → sending'),
        contains('header sync indicator sending → done'),
      ]),
    );
  });

  testUnmounting('нет сети и очередь пуста: «Ждёт сети» без числа, в плашке '
      '— что новое загрузится само', (tester) async {
    final server = SyncStatusServer()..mode = ServerMode.offline;
    final h = await startMonth(tester, server);

    await syncAndWait(h, SyncReason.periodic);
    expect(headerSync('Ждёт сети'), findsOneWidget);
    expect(headerIcon(AppIcons.cloudOff), findsOneWidget);

    await openPopover(tester, 'Ждёт сети');
    expect(inPopover(find.text('Ждёт сети · 0')), findsOneWidget);
    expect(
      inPopover(
        find.text(
          'Нет сети. Новое с сервера загрузится само, когда появится '
          'интернет.',
        ),
      ),
      findsOneWidget,
    );
    expect(
      inPopover(find.text('Синхронизировано · 2 мин назад')),
      findsOneWidget,
    );
  });

  testUnmounting('плашка «Ждёт сети · 3» как 47:6011: под шапкой справа, '
      '250 dp, текст про 3 изменения и время последней синхронизации; '
      'тап мимо закрывает', (tester) async {
    final server = SyncStatusServer()..mode = ServerMode.offline;
    final h = await startMonth(tester, server);
    await writeWhileShown(tester, () => addUnsyncedExpenses(h.db, 3));
    await syncAndWait(h, SyncReason.outbox);

    await openPopover(tester, 'Ждёт сети · 3');

    expect(popover, findsOneWidget);
    final status = tester.widget<SyncStatus>(
      inPopover(find.byType(SyncStatus)),
    );
    expect((status.state, status.pending), (SyncState.waiting, 3));
    expect(inPopover(find.text('Ждёт сети · 3')), findsOneWidget);
    expect(
      inPopover(
        find.text(
          'Нет сети. 3 изменения сохранены на телефоне и отправятся сами, '
          'когда появится интернет.',
        ),
      ),
      findsOneWidget,
    );
    expect(
      inPopover(find.text('Синхронизировано · 2 мин назад')),
      findsOneWidget,
    );
    expect(inPopover(find.text('Повторить')), findsNothing);
    final header = tester.getRect(find.byType(MonthHeaderView));
    final rect = tester.getRect(popover);
    expect(rect.width, 250);
    expect(rect.right, 360 - 12);
    expect(rect.top, header.bottom - 6);
    expect(
      h.linesOf('month', Level.FINE),
      contains(contains('header sync tap → sync status popover')),
    );

    await tester.tapAt(const Offset(40, 600));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
    expect(popover, findsNothing);
    expect(
      h.linesOf('sync', Level.FINE),
      contains(matches(r'sync status popover closed after \d+ms$')),
    );
  });

  testUnmounting('ошибка сервера: «Ошибка синхронизации» → тап → плашка с '
      '«Повторить» и временем последней; «Повторить» запускает движок, '
      'плашка показывает отправку и «Все изменения на сервере»', (
    tester,
  ) async {
    final server = SyncStatusServer()..mode = ServerMode.down;
    final h = await startMonth(tester, server);
    await writeWhileShown(tester, () => addUnsyncedExpenses(h.db, 3));
    await syncAndWait(h, SyncReason.outbox);

    expect(headerSync('Ошибка синхронизации'), findsOneWidget);
    expect(headerIcon(AppIcons.alertCircle), findsOneWidget);

    await openPopover(tester, 'Ошибка синхронизации');
    expect(inPopover(find.text('Ошибка синхронизации')), findsOneWidget);
    expect(
      inPopover(
        find.text(
          'Не получилось синхронизировать. 3 изменения сохранены на '
          'телефоне.',
        ),
      ),
      findsOneWidget,
    );
    expect(
      inPopover(find.text('Синхронизировано · 2 мин назад')),
      findsOneWidget,
    );
    expect(inPopover(find.text('Повторить')), findsOneWidget);

    server
      ..mode = ServerMode.online
      ..pushGate = Completer<void>();
    final before = server.calls.length;
    await tester.tap(inPopover(find.text('Повторить')));
    await pumpUntil(
      tester,
      () => inPopover(find.text('Отправляем…')).evaluate().isNotEmpty,
      reason: 'popover shows sending after retry',
    );
    expect(
      inPopover(find.text('Отправляем 3 изменения на сервер.')),
      findsOneWidget,
    );
    expect(headerSync('Отправляем…'), findsOneWidget);
    expect(inPopover(find.text('Повторить')), findsNothing);

    server.pushGate!.complete();
    await pumpUntil(
      tester,
      () =>
          inPopover(find.text('Все изменения на сервере.'))
              .evaluate()
              .isNotEmpty,
      reason: 'popover shows done after retry',
    );
    expect(
      [for (final c in server.calls.skip(before)) c.split('/').last],
      ['push', 'pull'],
    );
    expect(inPopover(find.text('Синхронизировано')), findsOneWidget);
    expect(
      inPopover(find.text('Синхронизировано · только что')),
      findsOneWidget,
    );
    expect(headerSync('Синхронизировано'), findsOneWidget);
    expect(
      h.linesOf('sync', Level.INFO),
      containsAllInOrder([
        endsWith(
          'sync status retry tap shown=error queue=3 failures=1 → sync '
          'reason=manual',
        ),
        contains('sync cycle start reason=manual attempt=2 queue=3'),
        contains('sync cycle done reason=manual'),
      ]),
    );
  });

  testUnmounting('идёт отправка: «Отправляем…» с вращающейся стрелкой, в '
      'плашке — сколько уходит; после — «Синхронизировано»', (tester) async {
    final server = SyncStatusServer()..pushGate = Completer<void>();
    final h = await startMonth(tester, server);
    await writeWhileShown(tester, () => addUnsyncedExpenses(h.db, 2));

    SyncCycleResult? result;
    unawaited(engineOf(h).sync(SyncReason.outbox).then((r) => result = r));
    await pumpUntil(
      tester,
      () => headerSync('Отправляем…').evaluate().isNotEmpty,
      reason: 'header shows sending',
    );
    expect(headerIcon(AppIcons.refresh), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(MonthHeaderView),
        matching: find.byType(RotationTransition),
      ),
      findsOneWidget,
    );

    await openPopover(tester, 'Отправляем…');
    expect(inPopover(find.text('Отправляем…')), findsOneWidget);
    expect(
      inPopover(find.text('Отправляем 2 изменения на сервер.')),
      findsOneWidget,
    );

    server.pushGate!.complete();
    await pumpUntil(tester, () => result != null, reason: 'sync cycle');
    await tester.pump(const Duration(milliseconds: 50));
    expect(result, isA<SyncCycleDone>());
    expect(headerSync('Синхронизировано'), findsOneWidget);
    expect(inPopover(find.text('Все изменения на сервере.')), findsOneWidget);
  });

  testUnmounting('синхронизация без изменений в очереди (таймер, websocket) '
      'не мигает «Отправляем…» в шапке', (tester) async {
    final server = SyncStatusServer()..pullGate = Completer<void>();
    final h = await startMonth(tester, server);

    SyncCycleResult? result;
    unawaited(engineOf(h).sync(SyncReason.periodic).then((r) => result = r));
    await pumpUntil(
      tester,
      () => engineOf(h).state.phase == SyncPhase.sending,
      reason: 'engine runs the cycle',
    );
    await tester.pump(const Duration(milliseconds: 50));
    expect(headerSync('Синхронизировано'), findsOneWidget);
    expect(headerIcon(AppIcons.refresh), findsNothing);

    server.pullGate!.complete();
    await pumpUntil(tester, () => result != null, reason: 'sync cycle');
    expect(result, isA<SyncCycleDone>());
    expect(headerSync('Синхронизировано'), findsOneWidget);
  });

  testUnmounting('«Синхронизировано»: плашка без «Повторить», в ней время '
      'последней синхронизации; в очереди есть ещё не отправленное — '
      '«скоро отправятся»', (tester) async {
    final server = SyncStatusServer();
    final h = await startMonth(tester, server);

    await openPopover(tester, 'Синхронизировано');
    expect(inPopover(find.text('Синхронизировано')), findsOneWidget);
    expect(inPopover(find.text('Все изменения на сервере.')), findsOneWidget);
    expect(
      inPopover(find.text('Синхронизировано · 2 мин назад')),
      findsOneWidget,
    );
    expect(inPopover(find.text('Повторить')), findsNothing);

    await writeWhileShown(tester, () => addUnsyncedExpenses(h.db, 2));
    expect(
      inPopover(
        find.text('2 изменения сохранены на телефоне и скоро отправятся.'),
      ),
      findsOneWidget,
    );
    expect(headerSync('Синхронизировано'), findsOneWidget);
  });

  for (final width in const [360.0, 320.0]) {
    for (final scale in const [1.0, 2.0]) {
      testUnmounting('${width.toInt()} dp, шрифт $scale: облако — кнопка не '
          'меньше 48 × 48, не заходит на поиск и аватар, нажимается у краёв', (
        tester,
      ) async {
        final server = SyncStatusServer();
        await startMonth(
          tester,
          server,
          size: Size(width, 800),
          textScale: scale,
        );
        expect(tester.takeException(), isNull);

        final sync = tester.getRect(headerSync('Синхронизировано'));
        final search = tester.getRect(headerSync('Поиск'));
        final avatar = tester.getRect(headerSync('Профиль'));
        expect(sync.width, greaterThanOrEqualTo(48));
        expect(sync.height, greaterThanOrEqualTo(48));
        expect(sync.left, greaterThanOrEqualTo(search.right));
        expect(sync.right, lessThanOrEqualTo(avatar.left));
        expect(avatar.right, lessThanOrEqualTo(width));
        final cloud = tester.getRect(headerIcon(AppIcons.cloudCheck));
        expect(sync.contains(cloud.center), isTrue);
        expect(
          tester.getSemantics(headerSync('Синхронизировано')),
          isSemantics(isButton: true, hasTapAction: true),
        );

        for (final point in [
          sync.topLeft + const Offset(1, 1),
          sync.bottomRight - const Offset(1, 1),
        ]) {
          await tester.tapAt(point);
          for (var i = 0; i < 10; i++) {
            await tester.pump(const Duration(milliseconds: 30));
          }
          expect(popover, findsOneWidget, reason: 'tap at $point');
          expect(tester.getRect(popover).right, lessThanOrEqualTo(width));
          await tester.binding.handlePopRoute();
          for (var i = 0; i < 10; i++) {
            await tester.pump(const Duration(milliseconds: 30));
          }
          expect(popover, findsNothing);
        }
      });
    }
  }
}
