import 'dart:io';

import 'package:drift/drift.dart' show Variable;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/data/repositories/prefs_repository.dart';
import 'package:milionchik/features/budgets/budget_switcher_sheet.dart';
import 'package:milionchik/features/budgets/join_budget_screen.dart';
import 'package:milionchik/features/month/month_screen.dart';
import 'package:milionchik/features/profile/profile_screen.dart';
import 'package:milionchik/ui/components/button.dart';
import 'package:milionchik/ui/components/snackbar.dart';
import 'package:shared/shared.dart';

import '../../data/api/fake_api_adapter.dart';
import '../../data/sync/pull_fixture.dart'
    show ownerOf, serverExpense, serverPresets;
import '../../support/app_scope.dart';
import '../auth/session_expired_fixture.dart' show testUnmounting;
import '../profile/profile_fixture.dart';
import '../profile/profile_harness.dart';

const String _field = 'Код';

const String _code = 'MLN-7QXW';

const String _tripId = 'budget-shared-trip';

const String _hint =
    'После входа бюджет появится в переключателе бюджетов, а все его траты '
    'загрузятся на этот телефон.';

const String _notFound = 'Код не найден или истёк. Попроси новый.';

const String _offline =
    'Нет связи с сервером — в бюджет не вошли. Проверь интернет и попробуй '
    'ещё раз';

const String _notLoaded =
    'Ты в бюджете, но он ещё не загрузился. Проверь интернет и нажми '
    '«Присоединиться» ещё раз';

final Budget _trip = Budget(
  id: _tripId,
  kind: BudgetKind.shared,
  name: 'Поездка',
  emoji: '✈️',
  ownerId: 'user-server-dima',
  createdAt: testNow.toUtc(),
  updatedAt: testNow.toUtc(),
  updatedBy: 'user-server-dima',
  seq: 300,
);

final class _Server {
  final Map<String, Budget> invites = {_code: _trip};
  bool offline = false;
  bool pullOffline = false;
  bool pullWithout = false;
  FakeReply? reject;
  final Set<String> joined = {};

  FakeReply handle(FakeCall call) {
    if (call.method == 'POST' && call.path.endsWith('/invites/join')) {
      if (offline) {
        throw const SocketException('Connection refused (test)');
      }
      final rejected = reject;
      if (rejected != null) return rejected;
      final budget = invites[call.json['code']];
      if (budget == null) {
        return FakeReply.error(404, 'invite_not_found', 'Код не найден');
      }
      joined.add(budget.id);
      return FakeReply.json(200, {'budget': budget.toJson()});
    }
    if (call.method == 'GET' && call.path.endsWith('/sync/pull')) {
      if (pullOffline) {
        throw const SocketException('Network is unreachable (test)');
      }
      if (pullWithout || !joined.contains(_tripId)) {
        return FakeReply.json(
          200,
          SyncPullResponse(cursor: 350, hasMore: false).toJson(),
        );
      }
      return FakeReply.json(
        200,
        SyncPullResponse(
          budgets: [_trip],
          members: [
            ownerOf(_tripId, userId: 'user-server-dima'),
            BudgetMember(
              budgetId: _tripId,
              userId: profileUserId,
              role: MemberRole.member,
              avatarColor: CategoryColor.green,
              joinedAt: testNow.toUtc(),
            ),
          ],
          categories: serverPresets(_tripId, firstSeq: 301),
          expenses: [
            serverExpense(
              id: 'expense-trip-1',
              budgetId: _tripId,
              categoryId: '$_tripId-cat-0',
              kopecks: 120000,
              seq: 320,
            ),
            serverExpense(
              id: 'expense-trip-2',
              budgetId: _tripId,
              categoryId: '$_tripId-cat-1',
              kopecks: 45000,
              seq: 321,
            ),
          ],
          cursor: 400,
          hasMore: false,
        ).toJson(),
      );
    }
    throw StateError('unexpected ${call.method} ${call.path}');
  }
}

Future<ProfileHarness> _openFromSwitcher(
  WidgetTester tester,
  _Server server,
) async {
  final h = await ProfileHarness.start(tester, server: server.handle);
  await tester.tap(find.bySemanticsLabel('Личный бюджет, выбрать бюджет'));
  await tester.pumpAndSettle();
  expect(find.byType(BudgetSheet), findsOneWidget);
  await h.tap(find.text('Войти по коду приглашения'));
  expect(find.byType(BudgetSheet), findsNothing);
  expect(find.byType(JoinBudgetScreen), findsOneWidget);
  return h;
}

Future<void> _join(ProfileHarness h) =>
    h.tap(find.widgetWithText(AppButton, 'Присоединиться'));

String _shown(ProfileHarness h) =>
    h.tester.widget<TextField>(h.input(_field)).controller!.text;

Finder _snackbar(String text) =>
    find.descendant(of: find.byType(AppSnackbar), matching: find.text(text));

Future<void> _dismissSnackbar(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 6));
  await tester.pumpAndSettle();
}

Future<String?> _storedChoice(ProfileHarness h) => h.tester.runAsync<String?>(
  () => DriftPrefsRepository(h.db).getString(PrefKeys.selectedBudgetId),
);

Future<({int budgets, int categories, int expenses})> _counts(
  ProfileHarness h,
) async => (await h.tester.runAsync(() async {
  Future<int> count(String sql, [List<String> args = const []]) async {
    final row = await h.db
        .customSelect(
          sql,
          variables: [for (final a in args) Variable.withString(a)],
        )
        .getSingle();
    return row.read<int>('n');
  }

  return (
    budgets: await count('SELECT count(*) AS n FROM budgets'),
    categories: await count(
      'SELECT count(*) AS n FROM categories WHERE budget_id = ?',
      [_tripId],
    ),
    expenses: await count(
      'SELECT count(*) AS n FROM expenses WHERE budget_id = ?',
      [_tripId],
    ),
  );
}))!;

List<FakeCall> _joins(ProfileHarness h) => h.adapter.callsTo('/invites/join');

List<FakeCall> _pulls(ProfileHarness h) => h.adapter.callsTo('/sync/pull');

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testUnmounting('шторка → «Войти по коду»; «mln 7qxw» в поле становится '
      'MLN-7QXW → POST /invites/join, pull, бюджет выбран, главная на нём, '
      'категории и траты с сервера; код в логах только MLN-****', (
    tester,
  ) async {
    final server = _Server();
    final h = await _openFromSwitcher(tester, server);

    expect(find.text(_hint), findsOneWidget);
    await h.enter(_field, 'mln 7qxw');
    expect(_shown(h), _code);
    await _join(h);

    expect(_joins(h).single.json, {'code': _code});
    expect(_pulls(h), hasLength(1));
    expect(find.byType(JoinBudgetScreen), findsNothing);
    expect(find.byType(MonthScreen), findsOneWidget);
    expect(find.bySemanticsLabel('Поездка, выбрать бюджет'), findsOneWidget);
    expect(await _storedChoice(h), _tripId);
    final counts = await _counts(h);
    expect(counts.budgets, 3);
    expect(counts.categories, 11);
    expect(counts.expenses, 2);
    expect(
      h.linesOf('budgets', Level.INFO),
      contains(
        matches(
          'INFO  \\[budgets\\] budget join ok budgetId=$_tripId '
          'code=MLN-\\*\\*\\*\\* status=200 categories=11 expenses=2 '
          'pulled=\\d+ cursor=400 rid=ridprofile000001 in \\d+ms → '
          'selected\$',
        ),
      ),
    );
    expect(
      h.linesOf('budgets', Level.INFO),
      contains(
        matches(
          'selected budget changed budgetId=$_tripId '
          'from=$profilePersonalId by=budget join in \\d+ms\$',
        ),
      ),
    );
    expect(h.logs.text, contains('MLN-****'));
    expect(h.logs.text, isNot(contains('7QXW')));
    expect(h.logs.text.toLowerCase(), isNot(contains('7qxw')));
  });

  testUnmounting('сервер: invite_not_found → «Код не найден или истёк. '
      'Попроси новый.» под полем (45:5138), подсказка под кнопкой скрыта, '
      'pull нет, выбор прежний; правка кода снимает ошибку', (tester) async {
    final server = _Server();
    final h = await _openFromSwitcher(tester, server);

    await h.enter(_field, 'MLN-7QX9');
    await _join(h);

    expect(_joins(h).single.json, {'code': 'MLN-7QX9'});
    expect(h.errorUnder(_field), _notFound);
    expect(find.text(_hint), findsNothing);
    expect(find.byType(AppSnackbar), findsNothing);
    expect(find.byType(JoinBudgetScreen), findsOneWidget);
    expect(_shown(h), 'MLN-7QX9');
    expect(_pulls(h), isEmpty);
    expect(await _storedChoice(h), isNull);
    expect(
      h.linesOf('budgets', Level.INFO),
      contains(
        matches(
          'budget join rejected code=MLN-\\*\\*\\*\\* reason=invite_not_found '
          'status=404 rid=ridprofile000001 in \\d+ms → error under the code '
          'field, not joined\$',
        ),
      ),
    );
    expect(h.logs.text, isNot(contains('7QX9')));

    await h.enter(_field, 'MLN-7QX');
    expect(h.errorUnder(_field), isNull);
    expect(find.text(_hint), findsOneWidget);
    expect(
      h.linesOf('budgets'),
      contains(
        endsWith(
          'join code edited after notFound → error under the field cleared',
        ),
      ),
    );

    await h.enter(_field, 'MLN-7QXW');
    await _join(h);
    expect(find.byType(MonthScreen), findsOneWidget);
    expect(await _storedChoice(h), _tripId);
  });

  testUnmounting('без сети: снекбар «в бюджет не вошли», ошибки под полем '
      'нет, pull нет; с сетью повтор входит', (tester) async {
    final server = _Server()..offline = true;
    final h = await _openFromSwitcher(tester, server);

    await h.enter(_field, _code);
    await _join(h);

    expect(_snackbar(_offline), findsOneWidget);
    expect(find.byType(JoinBudgetScreen), findsOneWidget);
    expect(h.errorUnder(_field), isNull);
    expect(_pulls(h), isEmpty);
    expect(await _storedChoice(h), isNull);
    expect(
      tester
          .widget<AppButton>(find.widgetWithText(AppButton, 'Присоединиться'))
          .onPressed,
      isNotNull,
    );
    expect(
      h.linesOf('budgets', Level.WARNING),
      contains(
        allOf(
          contains(
            'budget join failed code=MLN-**** ApiNetworkFailure: connection',
          ),
          contains('rid=ridprofile000001'),
          contains(
            '→ snackbar, not joined on this phone; a retry with the '
            'same code is safe',
          ),
        ),
      ),
    );
    expect(h.logs.text, isNot(contains('7QXW')));
    await _dismissSnackbar(tester);

    server.offline = false;
    await _join(h);

    expect(_joins(h), hasLength(2));
    expect(find.byType(MonthScreen), findsOneWidget);
    expect(await _storedChoice(h), _tripId);
  });

  testUnmounting('сервер принял код, а pull не прошёл: снекбар «ещё не '
      'загрузился», ничего не выбрано; повтор тем же кодом - вход', (
    tester,
  ) async {
    final server = _Server()..pullOffline = true;
    final h = await _openFromSwitcher(tester, server);

    await h.enter(_field, _code);
    await _join(h);

    expect(_snackbar(_notLoaded), findsOneWidget);
    expect(find.byType(JoinBudgetScreen), findsOneWidget);
    expect(await _storedChoice(h), isNull);
    expect((await _counts(h)).categories, 0);
    expect(
      h.linesOf('budgets', Level.WARNING),
      contains(
        allOf(
          contains(
            'budget join budgetId=$_tripId rid=ridprofile000001: pull failed '
            'stage=request ApiNetworkFailure: connection',
          ),
          contains('joined on the server but the budget is not on this phone'),
        ),
      ),
    );
    await _dismissSnackbar(tester);

    server.pullOffline = false;
    await _join(h);

    expect(_joins(h).map((c) => c.json['code']), [_code, _code]);
    expect(find.byType(MonthScreen), findsOneWidget);
    expect(await _storedChoice(h), _tripId);
    expect((await _counts(h)).expenses, 2);
  });

  testUnmounting('pull прошёл, но бюджета в нём нет: снекбар «ещё не '
      'загрузился», выбор не сохранён', (tester) async {
    final server = _Server()..pullWithout = true;
    final h = await _openFromSwitcher(tester, server);

    await h.enter(_field, _code);
    await _join(h);

    expect(_pulls(h), hasLength(1));
    expect(_snackbar(_notLoaded), findsOneWidget);
    expect(find.byType(JoinBudgetScreen), findsOneWidget);
    expect(await _storedChoice(h), isNull);
    expect(
      h.linesOf('budgets', Level.WARNING),
      contains(
        allOf(
          contains(
            'budget join budgetId=$_tripId rid=ridprofile000001: pull '
            'done',
          ),
          contains('but the budget is not in the local database'),
        ),
      ),
    );
    await _dismissSnackbar(tester);
  });

  testUnmounting('уже участник: сервер отвечает тем же бюджетом, pull '
      'ничего не приносит - бюджет уже на телефоне, он выбран', (tester) async {
    final family = Budget(
      id: profileFamilyId,
      kind: BudgetKind.shared,
      name: 'Семья',
      emoji: '🏠',
      ownerId: 'user-server-dima',
      createdAt: testNow.toUtc(),
      updatedAt: testNow.toUtc(),
      updatedBy: 'user-server-dima',
      seq: 5,
    );
    final server = _Server()..invites[_code] = family;
    final h = await _openFromSwitcher(tester, server);

    await h.enter(_field, _code);
    await _join(h);

    expect(_pulls(h), hasLength(1));
    expect(find.byType(MonthScreen), findsOneWidget);
    expect(find.bySemanticsLabel('Семья, выбрать бюджет'), findsOneWidget);
    expect(await _storedChoice(h), profileFamilyId);
    expect(
      h.linesOf('budgets', Level.INFO),
      contains(contains('budget join ok budgetId=$profileFamilyId')),
    );
  });

  testUnmounting('другая ошибка сервера (403): снекбар с текстом кода, '
      'ошибки под полем нет', (tester) async {
    final server = _Server()
      ..reject = FakeReply.error(403, 'forbidden', 'Нельзя');
    final h = await _openFromSwitcher(tester, server);

    await h.enter(_field, _code);
    await _join(h);

    expect(find.byType(AppSnackbar), findsOneWidget);
    expect(h.errorUnder(_field), isNull);
    expect(_pulls(h), isEmpty);
    expect(
      h.linesOf('budgets', Level.WARNING),
      contains(
        matches(
          'budget join rejected code=MLN-\\*\\*\\*\\* reason=forbidden '
          'status=403 rid=ridprofile000001 in \\d+ms → snackbar, not '
          'joined\$',
        ),
      ),
    );
    await _dismissSnackbar(tester);
  });

  testUnmounting('проверка до запроса: пусто - «Введи код приглашения», '
      'MLN-4 - «Нужно 4 символа после MLN-», запросов нет; правка кода '
      'снимает ошибку до следующего нажатия', (tester) async {
    final server = _Server();
    final h = await _openFromSwitcher(tester, server);

    expect(h.errorUnder(_field), isNull);
    await _join(h);
    expect(h.errorUnder(_field), 'Введи код приглашения');
    expect(find.text(_hint), findsNothing);

    await h.enter(_field, '4');
    expect(_shown(h), 'MLN-4');
    expect(h.errorUnder(_field), isNull);
    expect(find.text(_hint), findsOneWidget);
    await _join(h);
    expect(h.errorUnder(_field), 'Нужно 4 символа после MLN-');
    expect(h.adapter.calls, isEmpty);
    expect(
      h.linesOf('budgets', Level.INFO),
      containsAll([
        endsWith(
          'budget join blocked: code empty chars=0/4, error shown under the '
          'code field, no request',
        ),
        endsWith(
          'budget join blocked: code incomplete chars=1/4, error shown under '
          'the code field, no request',
        ),
      ]),
    );

    await h.enter(_field, '48K2');
    expect(_shown(h), 'MLN-48K2');
    expect(h.errorUnder(_field), isNull);
    expect(find.text(_hint), findsOneWidget);
    expect(
      h.linesOf('budgets'),
      contains(
        endsWith(
          'join code edited after incomplete → error under the field cleared',
        ),
      ),
    );
  });

  testUnmounting('автоформат при вводе по одному символу и стирании: M, ML, '
      'MLN, MLN-4 … MLN-48K2, пятый символ не входит; стирание снимает дефис '
      'вместе с последним символом', (tester) async {
    final h = await _openFromSwitcher(tester, _Server());

    final typed = <String>[];
    var text = '';
    for (final char in 'mln-48k2z'.split('')) {
      text = '${_shown(h)}$char';
      await h.enter(_field, text);
      typed.add(_shown(h));
    }
    expect(typed, [
      'M',
      'ML',
      'MLN',
      'MLN',
      'MLN-4',
      'MLN-48',
      'MLN-48K',
      'MLN-48K2',
      'MLN-48K2',
    ]);
    final selection = h.tester
        .widget<TextField>(h.input(_field))
        .controller!
        .selection;
    expect(selection, const TextSelection.collapsed(offset: 8));

    final erased = <String>[];
    for (var i = 0; i < 5; i++) {
      final current = _shown(h);
      await h.enter(_field, current.substring(0, current.length - 1));
      erased.add(_shown(h));
    }
    expect(erased, ['MLN-48K', 'MLN-48', 'MLN-4', 'MLN', 'ML']);
  });

  testUnmounting('профиль: «Войти по коду приглашения» открывает экран, '
      '«назад» возвращает в профиль без запросов', (tester) async {
    final h = await ProfileHarness.start(tester, server: _Server().handle);
    await h.openProfile();

    await h.tap(find.text('Войти по коду приглашения'));

    expect(find.byType(JoinBudgetScreen), findsOneWidget);
    expect(
      h.linesOf('profile'),
      contains(endsWith('profile row join budget tap → /budgets/join')),
    );

    await tester.tap(find.bySemanticsLabel('Назад').last);
    await h.settle();

    expect(find.byType(JoinBudgetScreen), findsNothing);
    expect(find.byType(ProfileScreen), findsOneWidget);
    expect(h.adapter.calls, isEmpty);
    expect(
      h.linesOf('nav'),
      contains(endsWith('join budget closed by back button')),
    );
  });
}
