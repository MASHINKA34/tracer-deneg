import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milionchik/data/current_user.dart';
import 'package:milionchik/data/db/app_database.dart';
import 'package:milionchik/data/repositories/categories_repository.dart';
import 'package:milionchik/data/repositories/expenses_repository.dart';
import 'package:milionchik/data/repositories/members_repository.dart';
import 'package:milionchik/data/repositories/outbox_queue.dart';
import 'package:milionchik/data/repositories/prefs_repository.dart';
import 'package:milionchik/features/export/export_budget_sheet.dart';
import 'package:milionchik/features/export/export_screen.dart';
import 'package:milionchik/ui/components/radio.dart';
import 'package:shared/shared.dart';

import '../../support/app_scope.dart';
import 'export_fixture.dart';

const String _shared = 'shared-1';

Future<void> _seedWithShared(AppDatabase db) async {
  await seedSmallExport(db);
  final user = LocalPrefsCurrentUser(DriftPrefsRepository(db));
  final outbox = DriftOutboxQueue(db);
  final at = DateTime.utc(2026, 10, 1);
  await testBudgets(db).applyFromServer([
    Budget(
      id: _shared,
      kind: BudgetKind.shared,
      name: 'Семья и друзья',
      emoji: '🏡',
      ownerId: 'u2',
      createdAt: at,
      updatedAt: at,
      updatedBy: 'u2',
    ),
  ]);
  var n = 0;
  final categories = buildPresetCategories(
    budgetId: _shared,
    updatedBy: 'u2',
    now: at,
    newId: () => 'shared-cat-${n++}',
  );
  final categoriesRepo = DriftCategoriesRepository(
    db,
    currentUser: user,
    outbox: outbox,
  );
  await categoriesRepo.applyFromServer(categories);
  String id(String name) => categories.singleWhere((c) => c.name == name).id;
  await DriftMembersRepository(db).applyProfilesFromServer([
    MemberProfile(
      userId: 'u2',
      displayName: 'Дима',
      avatarColor: CategoryColor.values.first,
    ),
  ]);
  final expenses = DriftExpensesRepository(
    db,
    currentUser: user,
    outbox: outbox,
  );
  Expense remote(
    String eid,
    String author,
    String category,
    int rubles,
    int day,
    String comment,
  ) => Expense(
    id: eid,
    budgetId: _shared,
    categoryId: id(category),
    amount: Money.rubles(rubles),
    spentOn: LocalDate(2026, 10, day),
    comment: comment,
    authorId: author,
    createdAt: DateTime.utc(2026, 10, day, 10),
    updatedAt: DateTime.utc(2026, 10, day, 10),
    updatedBy: author,
  );
  await expenses.applyFromServer([
    remote('shared-e1', 'u2', 'Кафе', 250, 3, 'Пицца'),
    remote('shared-e2', 'u3', 'Продукты', 1000, 4, ''),
  ]);
  await expenses.create(
    budgetId: _shared,
    categoryId: id('Кафе'),
    amount: const Money.rubles(99),
    spentOn: LocalDate(2026, 10, 6),
    comment: 'Кофе',
  );
}

Finder _option(String name) => find.descendant(
  of: find.byType(ExportBudgetSheet),
  matching: find.text(name),
);

bool _optionSelected(WidgetTester tester, String name) => tester
    .widget<AppRadio>(
      find.descendant(
        of: find.ancestor(of: _option(name), matching: find.byType(Row)).first,
        matching: find.byType(AppRadio),
      ),
    )
    .selected;

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testWidgets('строка бюджета открывает шторку со всеми бюджетами, выбран '
      'личный; «Семья и друзья» — своё имя файла, траты и авторы в колонке '
      '«Кто добавил»', (tester) async {
    final h = await ExportHarness.open(tester, seed: _seedWithShared);
    expect(find.bySemanticsLabel('Бюджет, Личный'), findsOneWidget);

    await tester.tap(find.byType(ExportBudgetRow));
    await h.settle();

    expect(find.byType(ExportBudgetSheet), findsOneWidget);
    expect(_option('Личный'), findsOneWidget);
    expect(_option('Семья и друзья'), findsOneWidget);
    expect(_optionSelected(tester, 'Личный'), isTrue);
    expect(_optionSelected(tester, 'Семья и друзья'), isFalse);

    await tester.tap(_option('Семья и друзья'));
    await h.settle();

    expect(find.byType(ExportBudgetSheet), findsNothing);
    expect(find.bySemanticsLabel('Бюджет, Семья и друзья'), findsOneWidget);
    expect(
      h.fileCardText,
      'milionchik_semya_i_druzya_2026-10.csv | 3 траты · 1 349 ₽',
    );

    await h.share();
    expect(utf8.decode(h.sharer.contents.single).split('\r\n'), [
      'Дата;Сумма;Категория;Комментарий;Бюджет;Кто добавил',
      '03.10.2026;250,00;Кафе;Пицца;Семья и друзья;Дима',
      '04.10.2026;1000,00;Продукты;;Семья и друзья;Удалённый участник',
      '06.10.2026;99,00;Кафе;Кофе;Семья и друзья;Я',
      '',
    ]);

    await tester.tap(find.byType(ExportBudgetRow));
    await h.settle();
    expect(_optionSelected(tester, 'Семья и друзья'), isTrue);
    await tester.tap(_option('Личный'));
    await h.settle();
    expect(
      h.fileCardText,
      'milionchik_lichnyj_2026-10.csv | 4 траты · 13 354 ₽',
    );
  });

  testWidgets('шторку бюджета закрыли жестом «назад» — бюджет прежний', (
    tester,
  ) async {
    final h = await ExportHarness.open(tester, seed: _seedWithShared);

    await tester.tap(find.byType(ExportBudgetRow));
    await h.settle();
    expect(find.byType(ExportBudgetSheet), findsOneWidget);
    await tester.binding.handlePopRoute();
    await h.settle();

    expect(find.byType(ExportBudgetSheet), findsNothing);
    expect(find.byType(ExportScreen), findsOneWidget);
    expect(
      h.fileCardText,
      'milionchik_lichnyj_2026-10.csv | 4 траты · 13 354 ₽',
    );
  });
}
