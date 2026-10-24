import 'dart:io';

import 'package:drift/drift.dart' show Variable;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/data/repositories/prefs_repository.dart';
import 'package:milionchik/features/budgets/budget_switcher_sheet.dart';
import 'package:milionchik/features/budgets/new_budget_screen.dart';
import 'package:milionchik/features/categories/category_emoji_sheet.dart';
import 'package:milionchik/features/month/month_screen.dart';
import 'package:milionchik/features/profile/profile_screen.dart';
import 'package:milionchik/ui/components/button.dart';
import 'package:milionchik/ui/components/snackbar.dart';
import 'package:shared/shared.dart';

import '../../data/api/fake_api_adapter.dart';
import '../../data/sync/pull_fixture.dart' show ownerOf, serverPresets;
import '../../support/app_scope.dart';
import '../auth/session_expired_fixture.dart' show testUnmounting;
import '../profile/profile_fixture.dart';
import '../profile/profile_harness.dart';

const String _name = 'Квартира';

const String _field = 'Название';

const String _offline =
    'Нет связи с сервером — бюджет не создан. Проверь интернет и попробуй '
    'ещё раз';

const String _notLoaded =
    'Бюджет создан, но ещё не загрузился. Проверь интернет и нажми «Создать '
    'бюджет» ещё раз';

final class _Server {
  bool offline = false;
  bool pullOffline = false;
  bool pullWithout = false;
  FakeReply? reject;
  final Map<String, Budget> created = {};

  Budget _budget(Map<String, Object?> body) => Budget(
    id: body['id']! as String,
    kind: BudgetKind.shared,
    name: normalizeText(body['name']! as String),
    emoji: body['emoji']! as String,
    ownerId: profileUserId,
    createdAt: testNow.toUtc(),
    updatedAt: testNow.toUtc(),
    updatedBy: profileUserId,
    seq: 100,
  );

  FakeReply handle(FakeCall call) {
    if (call.method == 'POST' && call.path.endsWith('/budgets')) {
      if (offline) {
        throw const SocketException('Connection refused (test)');
      }
      final rejected = reject;
      if (rejected != null) return rejected;
      final id = call.json['id']! as String;
      final known = created[id];
      final budget = known ?? (created[id] = _budget(call.json));
      return FakeReply.json(known == null ? 201 : 200, {
        'budget': budget.toJson(),
      });
    }
    if (call.method == 'GET' && call.path.endsWith('/sync/pull')) {
      if (pullOffline) {
        throw const SocketException('Network is unreachable (test)');
      }
      if (pullWithout) {
        return FakeReply.json(
          200,
          SyncPullResponse(cursor: 150, hasMore: false).toJson(),
        );
      }
      return FakeReply.json(
        200,
        SyncPullResponse(
          budgets: [...created.values],
          members: [for (final b in created.values) ownerOf(b.id)],
          categories: [
            for (final b in created.values)
              ...serverPresets(b.id, firstSeq: 101),
          ],
          cursor: 200,
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
  await h.tap(find.text('Создать общий бюджет'));
  expect(find.byType(BudgetSheet), findsNothing);
  expect(find.byType(NewBudgetScreen), findsOneWidget);
  return h;
}

Future<void> _create(ProfileHarness h) =>
    h.tap(find.widgetWithText(AppButton, 'Создать бюджет'));

Finder _snackbar(String text) =>
    find.descendant(of: find.byType(AppSnackbar), matching: find.text(text));

Future<void> _dismissSnackbar(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 6));
  await tester.pumpAndSettle();
}

Future<String?> _storedChoice(ProfileHarness h) => h.tester.runAsync<String?>(
  () => DriftPrefsRepository(h.db).getString(PrefKeys.selectedBudgetId),
);

Future<({int budgets, int categories, int outbox})> _counts(
  ProfileHarness h,
  String budgetId,
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
      [budgetId],
    ),
    outbox: await count('SELECT count(*) AS n FROM outbox'),
  );
}))!;

List<FakeCall> _posts(ProfileHarness h) => [
  for (final call in h.adapter.calls)
    if (call.method == 'POST' && call.path.endsWith('/budgets')) call,
];

List<FakeCall> _pulls(ProfileHarness h) => h.adapter.callsTo('/sync/pull');

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testUnmounting('«Создать общий бюджет» в шторке → экран; Квартира с '
      '👨‍👩‍👧 → POST /budgets, pull, бюджет выбран, главная на нём, 11 '
      'категорий с сервера; в логе budgetId, результат, rid и мс без '
      'названия', (tester) async {
    final server = _Server();
    final h = await _openFromSwitcher(tester, server);

    await h.enter(_field, '  $_name ');
    await h.tap(find.bySemanticsLabel('👨‍👩‍👧'));
    await _create(h);

    final post = _posts(h).single;
    final id = post.json['id']! as String;
    expect(isUuid(id), isTrue, reason: id);
    expect(post.json, {'id': id, 'name': _name, 'emoji': '👨‍👩‍👧'});
    expect(_pulls(h), hasLength(1));
    expect(find.byType(NewBudgetScreen), findsNothing);
    expect(find.byType(MonthScreen), findsOneWidget);
    expect(find.bySemanticsLabel('$_name, выбрать бюджет'), findsOneWidget);
    expect(await _storedChoice(h), id);
    final counts = await _counts(h, id);
    expect(counts.budgets, 3);
    expect(counts.categories, 11);
    expect(counts.outbox, 0);
    expect(
      h.linesOf('budgets', Level.INFO),
      contains(
        matches(
          'INFO  \\[budgets\\] budget create ok budgetId=$id result=created '
          'status=201 categories=11 pulled=\\d+ cursor=200 '
          'rid=ridprofile000001 in \\d+ms → selected\$',
        ),
      ),
    );
    expect(
      h.linesOf('budgets', Level.INFO),
      contains(
        matches(
          'selected budget changed budgetId=$id from=$profilePersonalId '
          'by=budget create in \\d+ms\$',
        ),
      ),
    );
    expect(h.logs.text, isNot(contains(_name)));
  });

  testUnmounting('без сети: снекбар «бюджет не создан», на телефоне ничего '
      'нового, выбор прежний; с сетью повтор уходит с тем же id', (
    tester,
  ) async {
    final server = _Server()..offline = true;
    final h = await _openFromSwitcher(tester, server);

    await h.enter(_field, _name);
    await _create(h);

    expect(_snackbar(_offline), findsOneWidget);
    expect(find.byType(NewBudgetScreen), findsOneWidget);
    expect(h.errorUnder(_field), isNull);
    expect(
      tester
          .widget<AppButton>(find.widgetWithText(AppButton, 'Создать бюджет'))
          .onPressed,
      isNotNull,
    );
    final first = _posts(h).single.json['id']! as String;
    expect(_pulls(h), isEmpty);
    final counts = await _counts(h, first);
    expect(counts.budgets, 2);
    expect(counts.categories, 0);
    expect(counts.outbox, 0);
    expect(await _storedChoice(h), isNull);
    expect(
      h.linesOf('budgets', Level.WARNING),
      contains(
        allOf(
          contains(
            'budget create failed budgetId=$first ApiNetworkFailure: '
            'connection',
          ),
          contains('rid=ridprofile000001'),
          contains('→ snackbar, nothing created on this phone'),
        ),
      ),
    );
    await _dismissSnackbar(tester);

    server.offline = false;
    await _create(h);

    final posts = _posts(h);
    expect(posts, hasLength(2));
    expect(posts.last.json['id'], first);
    expect(find.byType(MonthScreen), findsOneWidget);
    expect(await _storedChoice(h), first);
    expect(h.logs.text, isNot(contains(_name)));
  });

  testUnmounting('сервер создал, а pull не прошёл: снекбар «ещё не '
      'загрузился», ничего не выбрано; повтор - сервер отвечает 200 тем же '
      'бюджетом, pull, выбран (result=replayed)', (tester) async {
    final server = _Server()..pullOffline = true;
    final h = await _openFromSwitcher(tester, server);

    await h.enter(_field, _name);
    await _create(h);

    expect(_snackbar(_notLoaded), findsOneWidget);
    expect(find.byType(NewBudgetScreen), findsOneWidget);
    final id = _posts(h).single.json['id']! as String;
    expect((await _counts(h, id)).budgets, 2);
    expect(await _storedChoice(h), isNull);
    expect(
      h.linesOf('budgets', Level.WARNING),
      contains(
        allOf(
          contains(
            'budget create budgetId=$id result=created '
            'rid=ridprofile000001: pull failed stage=request '
            'ApiNetworkFailure: connection',
          ),
          contains('budget is on the server but not on this phone yet'),
        ),
      ),
    );
    await _dismissSnackbar(tester);

    server.pullOffline = false;
    await _create(h);

    expect(_posts(h).map((c) => c.json['id']), [id, id]);
    expect(server.created.keys, [id]);
    expect(find.byType(MonthScreen), findsOneWidget);
    expect(await _storedChoice(h), id);
    expect((await _counts(h, id)).categories, 11);
    expect(
      h.linesOf('budgets', Level.INFO),
      contains(contains('budget create ok budgetId=$id result=replayed')),
    );
  });

  testUnmounting('pull прошёл, но бюджета в нём нет: снекбар «ещё не '
      'загрузился», выбор не сохранён - иначе главная тут же вернулась бы на '
      'личный', (tester) async {
    final server = _Server()..pullWithout = true;
    final h = await _openFromSwitcher(tester, server);

    await h.enter(_field, _name);
    await _create(h);

    final id = _posts(h).single.json['id']! as String;
    expect(_pulls(h), hasLength(1));
    expect(_snackbar(_notLoaded), findsOneWidget);
    expect(find.byType(NewBudgetScreen), findsOneWidget);
    expect(await _storedChoice(h), isNull);
    expect(
      h.linesOf('budgets', Level.WARNING),
      contains(
        allOf(
          contains(
            'budget create budgetId=$id result=created '
            'rid=ridprofile000001: pull done',
          ),
          contains('but the budget is not in the local database'),
        ),
      ),
    );
    await _dismissSnackbar(tester);
  });

  testUnmounting('название: пустое и из пробелов - «Введи название бюджета», '
      '31 символ - «Не длиннее 30 символов», запроса нет; 30 символов '
      'проходят', (tester) async {
    final server = _Server();
    final h = await _openFromSwitcher(tester, server);

    expect(h.errorUnder(_field), isNull);
    await _create(h);
    expect(h.errorUnder(_field), 'Введи название бюджета');

    await h.enter(_field, '   ');
    await _create(h);
    expect(h.errorUnder(_field), 'Введи название бюджета');

    await h.enter(_field, 'б' * 31);
    expect(h.errorUnder(_field), 'Не длиннее 30 символов');
    await _create(h);
    expect(h.errorUnder(_field), 'Не длиннее 30 символов');
    expect(h.adapter.calls, isEmpty);
    expect(
      h.linesOf('budgets', Level.INFO),
      containsAll([
        matches(
          r'budget create blocked budgetId=\S+: budget_name_empty length=0 '
          r'max=30, error shown under the name field, no request$',
        ),
        matches(
          r'budget create blocked budgetId=\S+: budget_name_too_long '
          r'length=31 max=30, error shown under the name field, no request$',
        ),
      ]),
    );

    await h.enter(_field, 'б' * 30);
    expect(h.errorUnder(_field), isNull);
    await _create(h);
    expect(_posts(h).single.json['name'], 'б' * 30);
    expect(find.byType(MonthScreen), findsOneWidget);
  });

  testUnmounting('по умолчанию значок 🏡; «➕» открывает «Свой эмодзи» с '
      'подсказкой про бюджет, выбранный эмодзи уходит на сервер', (
    tester,
  ) async {
    final server = _Server();
    final h = await _openFromSwitcher(tester, server);

    expect(
      tester.getSemantics(find.bySemanticsLabel('🏡')),
      isSemantics(isButton: true, isSelected: true),
    );
    await h.tap(find.bySemanticsLabel('Другой эмодзи'));
    expect(find.byType(CategoryEmojiSheet), findsOneWidget);
    expect(
      find.text(
        'Открой эмодзи на клавиатуре и нажми на любой — он сразу станет '
        'значком бюджета.',
      ),
      findsOneWidget,
    );
    await tester.enterText(
      find.descendant(
        of: find.byType(CategoryEmojiSheet),
        matching: find.byType(TextField),
      ),
      '🎈',
    );
    await h.settle();

    expect(find.byType(CategoryEmojiSheet), findsNothing);
    expect(
      tester.getSemantics(find.bySemanticsLabel('🏡')),
      isSemantics(isButton: true, isSelected: false),
    );
    await h.enter(_field, _name);
    await _create(h);

    expect(_posts(h).single.json['emoji'], '🎈');
    expect(
      h.linesOf('budgets'),
      containsAll([
        endsWith('new budget ➕ tap → emoji keyboard sheet'),
        endsWith('new budget emoji set from=keyboard'),
      ]),
    );
  });

  testUnmounting('сервер отказал (409 conflict): снекбар, ничего не выбрано, '
      'следующая попытка - с новым id', (tester) async {
    final server = _Server()
      ..reject = FakeReply.error(409, 'conflict', 'Бюджет с таким id уже есть');
    final h = await _openFromSwitcher(tester, server);

    await h.enter(_field, _name);
    await _create(h);

    expect(
      _snackbar('Данные уже изменились. Обнови и попробуй снова'),
      findsOneWidget,
    );
    final first = _posts(h).single.json['id']! as String;
    expect(_pulls(h), isEmpty);
    expect(await _storedChoice(h), isNull);
    expect(
      h.linesOf('budgets', Level.INFO),
      contains(
        matches(
          'budget create rejected budgetId=$first code=conflict status=409 '
          'rid=ridprofile000001 in \\d+ms → snackbar, nothing created\$',
        ),
      ),
    );
    await _dismissSnackbar(tester);

    server.reject = null;
    await _create(h);

    final ids = _posts(h).map((c) => c.json['id']).toList();
    expect(ids, hasLength(2));
    expect(ids.last, isNot(first));
    expect(await _storedChoice(h), ids.last);
  });

  testUnmounting('профиль: «Создать общий бюджет» открывает экран, «назад» '
      'возвращает в профиль без запросов', (tester) async {
    final h = await ProfileHarness.start(tester, server: _Server().handle);
    await h.openProfile();

    await h.tap(find.text('Создать общий бюджет'));

    expect(find.byType(NewBudgetScreen), findsOneWidget);
    expect(
      h.linesOf('profile'),
      contains(endsWith('profile row create budget tap → /budgets/new')),
    );

    await tester.tap(find.bySemanticsLabel('Назад').last);
    await h.settle();

    expect(find.byType(NewBudgetScreen), findsNothing);
    expect(find.byType(ProfileScreen), findsOneWidget);
    expect(h.adapter.calls, isEmpty);
    expect(
      h.linesOf('nav'),
      contains(endsWith('new budget closed by back button')),
    );
  });
}
