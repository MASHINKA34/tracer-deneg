import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/data/sync/budget_removed_notice.dart';
import 'package:milionchik/data/sync/pull_service.dart';
import 'package:milionchik/data/sync/sync_engine.dart';
import 'package:milionchik/data/repositories/prefs_repository.dart';
import 'package:milionchik/features/budgets/budget_screen.dart';
import 'package:milionchik/features/budgets/budget_screen_view.dart';
import 'package:milionchik/features/budgets/budget_switcher_sheet.dart';
import 'package:milionchik/features/month/month_screen.dart';
import 'package:milionchik/features/profile/profile_screen.dart';
import 'package:milionchik/ui/components/button.dart';
import 'package:milionchik/ui/components/dialog.dart';
import 'package:milionchik/ui/components/sheet.dart';

import '../../data/api/fake_api_adapter.dart';
import '../../support/app_scope.dart';
import '../auth/session_expired_fixture.dart' show testUnmounting;
import '../profile/profile_fixture.dart';
import '../profile/profile_harness.dart';
import 'budget_screen_fixture.dart';

const String _deleted = 'Бюджет «Семья» удалён';

const String _excluded = 'Тебя исключили из бюджета «Семья»';

Future<void> _menu(ProfileHarness h) =>
    h.tap(find.bySemanticsLabel('Действия с бюджетом'));

Future<void> _confirm(ProfileHarness h, String label) =>
    h.tap(find.widgetWithText(AppButton, label));

List<FakeCall> _actions(ProfileHarness h) => [
  for (final call in h.adapter.calls)
    if (!call.path.endsWith('/sync/pull')) call,
];

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testUnmounting('создатель: участники с ролями и датой, блок «Пригласить», '
      'последние траты с авторами; «⋮» - только «Удалить бюджет»; долгий '
      'тап по участнику - «Исключить», по себе - ничего', (tester) async {
    final h = await openBudgetScreen(tester, BudgetServer(owner: true));

    expect(find.text('🏠 Семья'), findsOneWidget);
    expect(find.text('Общий бюджет · 3 участника'), findsOneWidget);
    expect(find.text('Аня (ты)'), findsOneWidget);
    expect(find.text('Создатель бюджета'), findsOneWidget);
    expect(find.text('Участник · с 2 октября'), findsOneWidget);
    expect(find.text('Участник · с 10 октября'), findsOneWidget);
    expect(find.text('Пригласить ещё кого-то'), findsOneWidget);
    expect(find.widgetWithText(AppButton, 'Пригласить'), findsOneWidget);
    expect(find.text('Лента · сегодня, 12:05'), findsOneWidget);
    expect(find.text('Коммуналка · вчера'), findsOneWidget);
    expect(find.text('Аптека · 17 октября'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp(r'^Продукты, Лента, .*добавил Дима$')),
      findsOneWidget,
    );

    await _menu(h);
    expect(find.byType(AppSheet), findsOneWidget);
    expect(find.text('Удалить бюджет'), findsOneWidget);
    expect(find.text('Выйти из бюджета'), findsNothing);
    await tester.tapAt(const Offset(180, 100));
    await h.settle();
    expect(find.byType(AppSheet), findsNothing);

    await longPressAndSettle(h, find.text('Аня (ты)'));
    expect(find.byType(AppSheet), findsNothing);

    await longPressAndSettle(h, find.text('Дима'));
    expect(find.byType(AppSheet), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AppSheet),
        matching: find.text('Исключить'),
      ),
      findsOneWidget,
    );
    expect(_actions(h), isEmpty);
  });

  testUnmounting('участник: нет блока «Пригласить» и кода; «⋮» - только '
      '«Выйти из бюджета»; долгий тап по участникам ничего не открывает', (
    tester,
  ) async {
    final h = await openBudgetScreen(tester, BudgetServer(owner: false));

    expect(find.text('Аня (ты)'), findsOneWidget);
    expect(find.text('Дима'), findsOneWidget);
    expect(find.text('Создатель бюджета'), findsOneWidget);
    expect(find.text('Пригласить ещё кого-то'), findsNothing);
    expect(find.byType(BudgetInviteCard), findsNothing);
    expect(find.text('Новый код'), findsNothing);

    await longPressAndSettle(h, find.text('Дима'));
    expect(find.byType(AppSheet), findsNothing);
    await longPressAndSettle(h, find.text('Мама'));
    expect(find.byType(AppSheet), findsNothing);

    await _menu(h);
    expect(find.text('Выйти из бюджета'), findsOneWidget);
    expect(find.text('Удалить бюджет'), findsNothing);
    expect(_actions(h), isEmpty);
  });

  testUnmounting('создатель удаляет: подтверждение, «Отмена» - запроса нет; '
      '«Удалить» → DELETE, pull, экран закрыт, в профиле снекбар «удалён» '
      'один, бюджет стёрт; в логе id, действие, результат, rid и мс без '
      'названия', (tester) async {
    final server = BudgetServer(owner: true);
    final h = await openBudgetScreen(tester, server, selected: true);

    await _menu(h);
    await h.tap(find.text('Удалить бюджет'));
    expect(find.text('Удалить бюджет «Семья»?'), findsOneWidget);
    await h.tap(find.widgetWithText(AppButton, 'Отмена'));
    expect(find.byType(AppDialog), findsNothing);
    expect(_actions(h), isEmpty);
    expect(find.byType(BudgetScreen), findsOneWidget);

    await _menu(h);
    await h.tap(find.text('Удалить бюджет'));
    await _confirm(h, 'Удалить');

    final call = _actions(h).single;
    expect((call.method, call.path), ('DELETE', '/api/v1/budgets/$familyId'));
    expect(h.adapter.callsTo('/sync/pull'), hasLength(1));
    expect(find.byType(BudgetScreen), findsNothing);
    expect(find.byType(ProfileScreen), findsOneWidget);
    expect(snackbarWith(_deleted), findsOneWidget);
    expect(await budgetRows(h), 1);
    expect(h.container.read(budgetRemovedNoticeProvider), isNull);
    expect(
      h.linesOf('budgets', Level.INFO),
      contains(
        matches(
          'INFO  \\[budgets\\] budget delete ok budgetId=$familyId '
          'status=204 synced=true rid=ridprofile000001 in \\d+ms\$',
        ),
      ),
    );
    expect(h.logs.text, isNot(contains('Семья')));
    await dismissSnackbar(tester);
  });

  testUnmounting('участник выходит из открытого «Семья»: POST leave, pull, '
      'снекбар «Ты больше не в бюджете», а не «Тебя исключили»; показан '
      'личный', (tester) async {
    final server = BudgetServer(owner: false);
    final h = await openBudgetScreen(tester, server, selected: true);

    await _menu(h);
    await h.tap(find.text('Выйти из бюджета'));
    expect(find.text('Выйти из бюджета «Семья»?'), findsOneWidget);
    await _confirm(h, 'Выйти');

    final call = _actions(h).single;
    expect(
      (call.method, call.path),
      ('POST', '/api/v1/budgets/$familyId/leave'),
    );
    expect(server.left, isTrue);
    expect(find.byType(BudgetScreen), findsNothing);
    expect(snackbarWith('Ты больше не в бюджете «Семья»'), findsOneWidget);
    expect(find.text(_excluded), findsNothing);
    expect(h.container.read(budgetRemovedNoticeProvider), isNull);
    expect(await budgetRows(h), 1);
    expect(
      h.linesOf('sync', Level.INFO),
      contains(
        contains(
          'selected budget removed budgetId=$familyId kind=shared '
          'as=excluded',
        ),
      ),
    );
    expect(
      h.linesOf('sync'),
      contains(
        contains(
          'budget removed notice budgetId=$familyId kind=excluded not '
          'posted: removed by own action on this phone',
        ),
      ),
    );
    await dismissSnackbar(tester);
  });

  testUnmounting('создатель исключает Диму: долгий тап → «Исключить» → '
      'подтверждение с именем → DELETE members, pull, строки Димы нет, '
      'снекбар «Дима больше не в бюджете»; имени в логе нет', (tester) async {
    final server = BudgetServer(owner: true);
    final h = await openBudgetScreen(tester, server);

    await longPressAndSettle(h, find.text('Дима'));
    await h.tap(
      find.descendant(
        of: find.byType(AppSheet),
        matching: find.text('Исключить'),
      ),
    );
    expect(find.text('Исключить участника?'), findsOneWidget);
    expect(
      find.text(
        'Дима больше не увидит бюджет «Семья». Траты, которые уже добавлены, '
        'останутся.',
      ),
      findsOneWidget,
    );
    await _confirm(h, 'Исключить');

    final call = _actions(h).single;
    expect(
      (call.method, call.path),
      ('DELETE', '/api/v1/budgets/$familyId/members/$dimaId'),
    );
    expect(server.removedMembers, [dimaId]);
    expect(find.byType(BudgetScreen), findsOneWidget);
    expect(find.text('Участник · с 2 октября'), findsNothing);
    expect(find.text('Общий бюджет · 2 участника'), findsOneWidget);
    expect(snackbarWith('Дима больше не в бюджете'), findsOneWidget);
    expect(
      h.linesOf('budgets', Level.INFO),
      contains(
        matches(
          'budget remove member ok budgetId=$familyId memberId=$dimaId '
          'status=204 synced=true rid=ridprofile000001 in \\d+ms\$',
        ),
      ),
    );
    expect(h.logs.text, isNot(contains('Дима')));
    await dismissSnackbar(tester);
  });

  testUnmounting('ошибка прав: сервер отвечает 403 forbidden на удаление → '
      'снекбар «Это может сделать только создатель бюджета», экран и бюджет '
      'на месте, роли перечитаны pull-ом', (tester) async {
    final server = BudgetServer(owner: true)
      ..reject = FakeReply.error(
        403,
        'forbidden',
        'Это может сделать только создатель бюджета',
      );
    final h = await openBudgetScreen(tester, server);

    await _menu(h);
    await h.tap(find.text('Удалить бюджет'));
    await _confirm(h, 'Удалить');

    expect(
      snackbarWith('Это может сделать только создатель бюджета'),
      findsOneWidget,
    );
    expect(find.byType(BudgetScreen), findsOneWidget);
    expect(server.deleted, isFalse);
    expect(await budgetRows(h), 2);
    expect(h.adapter.callsTo('/sync/pull'), hasLength(1));
    expect(
      h.linesOf('budgets', Level.INFO),
      contains(
        contains(
          'budget delete rejected budgetId=$familyId reason=forbidden '
          'status=403 rid=ridprofile000001',
        ),
      ),
    );
    await dismissSnackbar(tester);
  });

  for (final (deleted, text) in [(false, _excluded), (true, _deleted)]) {
    testUnmounting(
      'участнику на экране «Семья» ${deleted ? 'бюджет удалили' : 'его исключили'}: '
      'после pull экран закрыт, снекбар движка «$text», показан личный',
      (tester) async {
        final server = BudgetServer(owner: false);
        final h = await openBudgetScreen(tester, server, selected: true);
        if (deleted) {
          server.deletedByOwner = true;
        } else {
          server.excludedByOwner = true;
        }

        final pulled = h.container
            .read(syncEngineProvider)
            .pullNow(PullReason.websocket);
        await h.settle();
        await h.settle();
        expect((await pulled)!.removedBudgets.single.budgetId, familyId);

        expect(find.byType(BudgetScreen), findsNothing);
        expect(find.text(text), findsOneWidget);
        expect(await budgetRows(h), 1);
        expect(
          h.linesOf('budgets', Level.INFO),
          contains(
            endsWith(
              'budget screen budgetId=$familyId: budget is not on this phone '
              '(removed by sync) → screen closed',
            ),
          ),
        );
        expect(profileFamilyId, familyId);
        await dismissSnackbar(tester);
      },
    );
  }

  testUnmounting('шторка бюджетов: тап по открытому общему «Семья» - экран '
      'бюджета; «назад» - снова главная', (tester) async {
    final db = openTestDatabase();
    await tester.runAsync(() async {
      await BudgetScreenFixture.seed(db, owner: true);
      await DriftPrefsRepository(db)
          .setString(PrefKeys.selectedBudgetId, familyId);
    });
    final h = await ProfileHarness.start(
      tester,
      server: BudgetServer(owner: true).handle,
      seed: false,
      db: db,
    );
    await tester.tap(find.bySemanticsLabel('Семья, выбрать бюджет'));
    await h.settle();
    expect(find.byType(BudgetSheet), findsOneWidget);

    await h.tap(
      find.descendant(
        of: find.byType(BudgetSheet),
        matching: find.text('Семья'),
      ),
    );

    expect(find.byType(BudgetSheet), findsNothing);
    expect(find.byType(BudgetScreen), findsOneWidget);
    expect(
      h.linesOf('budgets'),
      contains(
        endsWith(
          'budget switcher: shared budgetId=$familyId is already open → '
          '/budgets/:id',
        ),
      ),
    );

    await h.tap(find.bySemanticsLabel('Назад'));
    expect(find.byType(BudgetScreen), findsNothing);
    expect(find.byType(MonthScreen), findsOneWidget);
    expect(h.adapter.calls, isEmpty);
  });
}
