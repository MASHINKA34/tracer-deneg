import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/core/router.dart';
import 'package:milionchik/features/categories/categories_screen.dart';
import 'package:milionchik/features/categories/category_editor_screen.dart';
import 'package:milionchik/l10n/app_localizations.dart';
import 'package:milionchik/ui/components/button.dart';
import 'package:milionchik/ui/components/dialog.dart';
import 'package:milionchik/ui/components/snackbar.dart';

import 'categories_harness.dart';

Finder _inDialog(Finder finder) =>
    find.descendant(of: find.byType(AppDialog), matching: finder);

Future<void> _tapDelete(CategoriesHarness h) async {
  await h.tapButton(h.deleteButton);
  await h.pumpUntil(find.byType(AppDialog));
}

Future<void> _openDelete(CategoriesHarness h, String name) async {
  await h.openList();
  await h.tapRow(name);
  await _tapDelete(h);
}

void main() {
  testWidgets('«Здоровье» с 3 тратами: диалог «Удалить «Здоровье»?» с «3 траты '
      'перейдут в категорию «Другое»», «Удалить» → назад к списку, траты в '
      '«Другом», info с числом перенесённых', (tester) async {
    final h = await CategoriesHarness.start(tester);
    final health = await h.named('Здоровье');
    final other = await h.read(h.fixture.other);
    final before = await h.read(() => h.fixture.expensesOf(health.id));
    final otherBefore = await h.read(() => h.fixture.expensesOf(other.id));
    expect(before, hasLength(3));
    expect(otherBefore, isEmpty);

    await _openDelete(h, 'Здоровье');

    expect(find.byType(AppDialog), findsOneWidget);
    expect(_inDialog(find.text('Удалить «Здоровье»?')), findsOneWidget);
    expect(
      _inDialog(
        find.text(
          '3 траты перейдут в категорию «Другое». Сами траты и суммы не '
          'пропадут. Отменить удаление нельзя.',
        ),
      ),
      findsOneWidget,
    );
    expect(_inDialog(find.widgetWithText(AppButton, 'Отмена')), findsOneWidget);

    await tester.tap(_inDialog(find.widgetWithText(AppButton, 'Удалить')));
    await tester.pumpAndSettle();

    expect(find.byType(AppDialog), findsNothing);
    expect(find.byType(CategoryEditorScreen), findsNothing);
    expect(find.byType(CategoriesScreen), findsOneWidget);
    expect(h.location, AppRoutes.categories);
    expect(h.inList(find.text('Здоровье')), findsNothing);
    expect(await h.stored(), hasLength(10));
    expect(await h.read(() => h.fixture.expensesOf(health.id)), isEmpty);
    final moved = await h.read(() => h.fixture.expensesOf(other.id));
    expect(moved.map((e) => e.id).toSet(), before.map((e) => e.id).toSet());
    expect(
      moved.map((e) => e.amount).toList()..sort(),
      before.map((e) => e.amount).toList()..sort(),
    );
    final info = h.logs(Level.INFO).toList();
    expect(info, hasLength(1));
    expect(
      info.single.message,
      matches(
        'category deleted id=${health.id} budgetId=${h.fixture.budgetId} '
        'movedExpenses=3 movedRecurring=0 shown=3 other=${other.id} '
        r'in \d+ms$',
      ),
    );
    expect(
      h.messages(),
      containsAllInOrder([
        'category delete tap id=${health.id} → counting expenses to move',
        matches(
          'category delete id=${health.id} budgetId=${h.fixture.budgetId} '
          r'expenses=3 to move in \d+ms$',
        ),
      ]),
    );
    for (final r in h.shell.records) {
      expect(r.message, isNot(contains('Здоровье')), reason: r.message);
    }
    expect(
      h.shell.navDebug(),
      contains('category editor closed id=${health.id} by delete'),
    );
  });

  testWidgets('«Отмена» и «назад» в диалоге ничего не удаляют, редактор '
      'остаётся', (tester) async {
    final h = await CategoriesHarness.start(tester);
    final cafe = await h.named('Кафе');
    await _openDelete(h, 'Кафе');
    expect(
      _inDialog(find.textContaining('11 трат перейдут в категорию «Другое».')),
      findsOneWidget,
    );

    await tester.tap(_inDialog(find.widgetWithText(AppButton, 'Отмена')));
    await tester.pumpAndSettle();
    expect(find.byType(AppDialog), findsNothing);
    expect(find.byType(CategoryEditorScreen), findsOneWidget);

    await _tapDelete(h);
    await h.shell.systemBack();
    expect(find.byType(AppDialog), findsNothing);
    expect(find.byType(CategoryEditorScreen), findsOneWidget);

    expect((await h.stored()).map((c) => c.id), contains(cafe.id));
    expect(await h.read(() => h.fixture.expensesOf(cafe.id)), hasLength(11));
    expect(h.messages(Level.INFO), isEmpty);
    expect(
      h.messages(),
      containsAllInOrder([
        'category delete id=${cafe.id} dialog → cancel: nothing deleted',
        'category delete id=${cafe.id} dialog dismissed: nothing deleted',
      ]),
    );
  });

  testWidgets('число в диалоге настоящее: «Спорт» — «1 трата перейдёт», '
      '«Подарки» без трат — «Трат в этой категории нет»', (tester) async {
    final h = await CategoriesHarness.start(tester);
    await _openDelete(h, 'Спорт');
    expect(
      _inDialog(
        find.text(
          '1 трата перейдёт в категорию «Другое». Сами траты и суммы не '
          'пропадут. Отменить удаление нельзя.',
        ),
      ),
      findsOneWidget,
    );
    await h.shell.systemBack();
    await h.shell.systemBack();

    await h.tapRow('Подарки');
    await _tapDelete(h);
    expect(
      _inDialog(
        find.text('Трат в этой категории нет. Отменить удаление нельзя.'),
      ),
      findsOneWidget,
    );
    await tester.tap(_inDialog(find.widgetWithText(AppButton, 'Удалить')));
    await tester.pumpAndSettle();
    expect(h.inList(find.text('Подарки')), findsNothing);
    expect(
      h.messages(Level.INFO).single,
      contains('movedExpenses=0 movedRecurring=0 shown=0'),
    );
  });

  test('окончания «N трат перейдут» по-русски', () async {
    final l10n = await AppLocalizations.delegate.load(const Locale('ru'));
    String head(int n) => l10n.categoryDeleteMessage(n).split('.').first;
    expect(head(1), '1 трата перейдёт в категорию «Другое»');
    expect(head(2), '2 траты перейдут в категорию «Другое»');
    expect(head(4), '4 траты перейдут в категорию «Другое»');
    expect(head(5), '5 трат перейдут в категорию «Другое»');
    expect(head(11), '11 трат перейдут в категорию «Другое»');
    expect(head(21), '21 трата перейдёт в категорию «Другое»');
    expect(head(22), '22 траты перейдут в категорию «Другое»');
    expect(head(0), 'Трат в этой категории нет');
    expect(l10n.categoriesExpenses(0), '0 трат');
    expect(l10n.categoriesExpenses(1), '1 трата');
    expect(l10n.categoriesExpenses(3), '3 траты');
    expect(l10n.categoriesExpenses(58), '58 трат');
  });

  testWidgets('ошибка удаления в базе: снекбар «Не удалось удалить '
      'категорию», редактор остаётся, траты на месте, error без параметров '
      'SQL', (tester) async {
    final h = await CategoriesHarness.start(tester);
    final cafe = await h.named('Кафе');
    await h.write(
      () => h.shell.db.customStatement(
        'CREATE TRIGGER expenses_fail BEFORE UPDATE ON expenses '
        "BEGIN SELECT RAISE(ABORT, 'disk I/O error'); END",
      ),
    );
    await _openDelete(h, 'Кафе');
    await tester.tap(_inDialog(find.widgetWithText(AppButton, 'Удалить')));
    await tester.pumpAndSettle();

    expect(find.byType(CategoryEditorScreen), findsOneWidget);
    expect(find.byType(AppSnackbar), findsOneWidget);
    expect(
      find.text('Не удалось удалить категорию. Попробуй ещё раз'),
      findsOneWidget,
    );
    expect(h.inEditor(find.text('Кафе')), findsOneWidget);
    expect(await h.read(() => h.fixture.expensesOf(cafe.id)), hasLength(11));
    final errors = h.logs(Level.SEVERE).toList();
    expect(errors, hasLength(1));
    expect(
      errors.single.message,
      matches(
        '^category delete failed id=${cafe.id} budgetId=${h.fixture.budgetId} '
        r'after \d+ms, nothing deleted: SqliteException',
      ),
    );
    expect(errors.single.message, contains('disk I/O error'));
  });

  testWidgets('«Другое» по адресу /categories/<id>: экран «Другое» не '
      'меняется» без полей и кнопок удаления, «Назад» к списку', (
    tester,
  ) async {
    final h = await CategoriesHarness.start(tester);
    final other = await h.read(h.fixture.other);
    await h.openList();

    await h.go(AppRoutes.categoryOf(other.id));

    expect(find.byType(CategoryEditorScreen), findsOneWidget);
    expect(h.inEditor(find.text('«Другое» не меняется')), findsOneWidget);
    expect(h.saveButton, findsNothing);
    expect(h.deleteButton, findsNothing);
    expect(
      h.messages(Level.WARNING),
      contains(
        'category editor id=${other.id} is the system category → read-only '
        'screen, editing and deleting are not allowed',
      ),
    );
    await tester.tap(h.inEditor(find.widgetWithText(AppButton, 'Назад')));
    await tester.pumpAndSettle();
    expect(h.location, AppRoutes.categories);
    expect((await h.read(h.fixture.other)).name, 'Другое');
  });

  testWidgets('несуществующая категория — «Категория не найдена»; удалённая '
      'при открытом редакторе — тоже, с info', (tester) async {
    final h = await CategoriesHarness.start(tester);
    final dom = await h.named('Дом');
    await h.openList();
    await h.go(AppRoutes.categoryOf('no-such-category'));
    expect(h.inEditor(find.text('Категория не найдена')), findsOneWidget);
    expect(
      h.messages(Level.WARNING),
      contains(
        'category editor id=no-such-category: category is not found or '
        'deleted → not found screen',
      ),
    );
    await h.shell.systemBack();

    await h.tapRow('Дом');
    await h.write(() => h.fixture.categories.delete(dom.id));

    expect(h.inEditor(find.text('Категория не найдена')), findsOneWidget);
    expect(
      h.messages(Level.INFO),
      contains(
        'category editor id=${dom.id}: category was deleted while the screen '
        'was open → not found screen',
      ),
    );
  });
}
