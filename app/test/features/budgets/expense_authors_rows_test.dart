import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/core/router.dart';
import 'package:milionchik/data/repositories/prefs_repository.dart';
import 'package:milionchik/features/budgets/budget_screen.dart';
import 'package:milionchik/features/month/day_sheet.dart';
import 'package:milionchik/features/month/today_block.dart';
import 'package:milionchik/features/search/search_screen.dart';
import 'package:milionchik/ui/components/avatar.dart';
import 'package:milionchik/ui/components/category_badge.dart';
import 'package:milionchik/ui/components/expense_row.dart';
import 'package:milionchik/ui/tokens/tokens.g.dart';
import 'package:shared/shared.dart';

import '../../support/app_scope.dart';
import '../auth/session_expired_fixture.dart' show testUnmounting;
import 'expense_authors_fixture.dart';

typedef _Avatar = (String letter, Color color);

final Color _green = categoryLight[CategoryColor.green]!.solid;

final Color _blue = categoryLight[CategoryColor.blue]!.solid;

final Color _pink = categoryLight[CategoryColor.pink]!.solid;

final Color _neutral = neutralLight.textTertiary;

List<_Avatar> _avatars(WidgetTester tester, Finder scope) {
  final rows = find.descendant(of: scope, matching: find.byType(ExpenseRow));
  return [
    for (final avatar in tester.widgetList<AppAvatar>(
      find.descendant(of: rows, matching: find.byType(AppAvatar)),
    ))
      (avatar.letter, _fill(tester, avatar)),
  ];
}

Color _fill(WidgetTester tester, AppAvatar avatar) {
  final box = tester.widget<Container>(
    find.descendant(
      of: find.byWidget(avatar),
      matching: find.byType(Container),
    ),
  );
  return (box.decoration! as BoxDecoration).color!;
}

int _rows(Finder scope) => find
    .descendant(of: scope, matching: find.byType(ExpenseRow))
    .evaluate()
    .length;

Future<void> _openDay(WidgetTester tester) async {
  await tester.tap(find.bySemanticsLabel(RegExp('^19 октября')));
  await tester.pumpAndSettle();
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 20)),
  );
  await tester.pumpAndSettle();
}

Future<void> _search(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(EditableText), text);
  await tester.pump(searchDebounce);
  await tester.pumpAndSettle();
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 50)),
  );
  await tester.pumpAndSettle();
}

void main() {
  late List<LogRecord> records;
  late StreamSubscription<LogRecord> sub;

  setUpAll(() => initializeDateFormatting('ru'));

  setUp(() {
    records = [];
    Logger.root.level = Level.ALL;
    sub = Logger.root.onRecord.listen(records.add);
  });

  tearDown(() async {
    await sub.cancel();
    Logger.root.level = Level.INFO;
  });

  testUnmounting('общий бюджет: на главной, в шторке дня, в поиске и на '
      'экране бюджета у каждой траты аватар автора - буква и цвет '
      'участника; в TalkBack - «добавил …»; в личном - без аватара', (
    tester,
  ) async {
    final db = openTestDatabase();
    await tester.runAsync(() => seedAuthors(db));
    await pumpAuthorsApp(tester, db, location: AppRoutes.month);

    final today = find.byType(TodayBlock);
    expect(_avatars(tester, today), [
      ('Д', _green),
      ('А', _blue),
      ('М', _pink),
    ]);
    expect(
      find.bySemanticsLabel(
        RegExp(r'^Продукты, Лента, 12:05, .*добавил Дима$'),
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp(r'^Дом, Коммуналка, 09:30, .*добавил Аня$')),
      findsOneWidget,
    );

    await _openDay(tester);
    final sheet = find.byType(DaySheet);
    expect(_avatars(tester, sheet).toSet(), {
      ('Д', _green),
      ('А', _blue),
      ('М', _pink),
    });
    expect(
      find.descendant(
        of: sheet,
        matching: find.bySemanticsLabel(RegExp(r'^Здоровье, .*добавил Мама$')),
      ),
      findsOneWidget,
    );

    await pumpAuthorsApp(tester, db, location: AppRoutes.search);
    await _search(tester, 'а');
    expect(_avatars(tester, find.byType(SearchScreen)), [
      ('Д', _green),
      ('А', _blue),
      ('М', _pink),
    ]);

    await pumpAuthorsApp(tester, db, location: AppRoutes.budgetOf(familyId));
    expect(_avatars(tester, find.byType(BudgetScreen)), [
      ('Д', _green),
      ('А', _blue),
      ('М', _pink),
    ]);

    await tester.runAsync(
      () =>
          DriftPrefsRepository(db)
              .setString(PrefKeys.selectedBudgetId, personalId),
    );
    await pumpAuthorsApp(tester, db, location: AppRoutes.month);
    final personal = find.byType(TodayBlock);
    expect(_rows(personal), 1);
    expect(_avatars(tester, personal), isEmpty);
    expect(
      find.bySemanticsLabel(RegExp(r'^Кафе, Кофе, 11:00, [^,]+$')),
      findsOneWidget,
    );

    await _openDay(tester);
    final personalDay = find.byType(DaySheet);
    expect(_rows(personalDay), 1);
    expect(_avatars(tester, personalDay), isEmpty);

    await pumpAuthorsApp(tester, db, location: AppRoutes.search);
    await _search(tester, 'кофе');
    final personalSearch = find.byType(SearchScreen);
    expect(_rows(personalSearch), 1);
    expect(_avatars(tester, personalSearch), isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final (state, how) in const [
    (MamaState.left, 'вышла или исключена - профиль на телефоне остался'),
    (MamaState.deleted, 'удалила аккаунт - сервер прислал профиль без имени'),
  ]) {
    testUnmounting('автор $how: «Удалённый участник», нейтральный серый '
        'аватар «У», значок категории своего цвета', (tester) async {
      final db = openTestDatabase();
      await tester.runAsync(() => seedAuthors(db, mama: state));
      await pumpAuthorsApp(tester, db, location: AppRoutes.month);

      final today = find.byType(TodayBlock);
      expect(_avatars(tester, today), [
        ('Д', _green),
        ('А', _blue),
        ('У', _neutral),
      ]);
      expect(
        find.bySemanticsLabel(
          RegExp(r'^Здоровье, Аптека, 08:00, .*добавил Удалённый участник$'),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Мама'), findsNothing);
      final health = find.descendant(
        of: today,
        matching: find.byWidgetPredicate(
          (w) => w is ExpenseRow && w.title == 'Здоровье',
        ),
      );
      final badge = tester.widget<Container>(
        find.descendant(
          of: find.descendant(of: health, matching: find.byType(CategoryBadge)),
          matching: find.byType(Container),
        ),
      );
      expect(
        (badge.decoration! as BoxDecoration).color,
        categoryLight[tester.widget<ExpenseRow>(health).color]!.soft,
      );

      await _openDay(tester);
      expect(
        _avatars(tester, find.byType(DaySheet)),
        contains(('У', _neutral)),
      );

      await pumpAuthorsApp(tester, db, location: AppRoutes.budgetOf(familyId));
      expect(_avatars(tester, find.byType(BudgetScreen)), [
        ('Д', _green),
        ('А', _blue),
        ('У', _neutral),
      ]);
      expect(tester.takeException(), isNull);
    });
  }

  testUnmounting('участник без профиля на телефоне: у его траты аватара нет, '
      'в логе debug «author profile missing» с userId, имён в логе нет', (
    tester,
  ) async {
    final db = openTestDatabase();
    await tester.runAsync(() => seedAuthors(db, mama: MamaState.noProfile));
    await pumpAuthorsApp(tester, db, location: AppRoutes.month);

    final today = find.byType(TodayBlock);
    expect(_rows(today), 3);
    expect(_avatars(tester, today), [('Д', _green), ('А', _blue)]);
    final missing = records
        .where((r) => r.message.startsWith('author profile missing'))
        .toList();
    expect(missing, isNotEmpty);
    expect(missing.map((r) => (r.loggerName, r.level)).toSet(), {
      ('budgets', Level.FINE),
    });
    expect(
      missing.first.message,
      startsWith(
        'author profile missing userId=$mamaId budgetId=$familyId members=3 '
        'profiles=1: active member → no avatar',
      ),
    );
    for (final r in records) {
      expect(r.message, isNot(contains('Дима')));
      expect(r.message, isNot(contains('Аня')));
    }
  });

  testUnmounting('правка траты общего бюджета: «Добавил: Дима», своя - '
      '«Добавил: Аня»; автора нет в бюджете - «Добавил: Удалённый участник» '
      'серым; в личном строки нет', (tester) async {
    final db = openTestDatabase();
    await tester.runAsync(() => seedAuthors(db, mama: MamaState.deleted));
    final author = find.byKey(const ValueKey('edit-expense-author'));

    await pumpAuthorsApp(tester, db, location: AppRoutes.expenseOf(foodId));
    expect(find.text('Добавил: Дима'), findsOneWidget);

    await pumpAuthorsApp(tester, db, location: AppRoutes.expenseOf(homeId));
    expect(find.text('Добавил: Аня'), findsOneWidget);

    await pumpAuthorsApp(tester, db, location: AppRoutes.expenseOf(healthId));
    expect(find.text('Добавил: Удалённый участник'), findsOneWidget);
    expect(tester.widget<Text>(author).style?.color, _neutral);

    await pumpAuthorsApp(tester, db, location: AppRoutes.expenseOf(coffeeId));
    expect(find.textContaining('Добавил'), findsNothing);
    expect(author, findsNothing);
    expect(tester.takeException(), isNull);
  });
}
