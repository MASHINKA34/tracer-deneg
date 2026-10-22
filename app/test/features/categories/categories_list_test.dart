import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/core/router.dart';
import 'package:milionchik/features/categories/categories_screen.dart';
import 'package:milionchik/features/categories/category_editor_screen.dart';
import 'package:milionchik/ui/components/category_badge.dart';
import 'package:milionchik/ui/icons/app_icon.dart';

import 'categories_fixture.dart';
import 'categories_harness.dart';

void main() {
  testWidgets('«Настроить» в «Новой трате» → «Категории»: категории бюджета '
      'по порядку с числом трат, «Другое» последней с подписью и без '
      'шеврона', (tester) async {
    final h = await CategoriesHarness.start(tester);
    await h.shell.tapPlus();
    await tester.tap(find.text('Настроить').first);
    await tester.pumpAndSettle();

    expect(find.byType(CategoriesScreen), findsOneWidget);
    expect(h.location, AppRoutes.categories);
    expect(h.inList(find.text('Категории')), findsOneWidget);
    final names = [for (final (name, _) in mockupCategoryCounts) name];
    expect(h.shownNames([...names, 'Другое']), [...names, 'Другое']);
    expect(h.inList(find.byType(CategoryBadge)), findsNWidgets(11));
    expect(h.rowLabel('Продукты'), 'Продукты, 58 трат');
    expect(h.rowLabel('Кафе'), 'Кафе, 11 трат');
    expect(h.rowLabel('Здоровье'), 'Здоровье, 3 траты');
    expect(h.rowLabel('Развлечения'), 'Развлечения, 4 траты');
    expect(h.rowLabel('Спорт'), 'Спорт, 1 трата');
    expect(h.rowLabel('Подарки'), 'Подарки, 0 трат');
    expect(
      h.rowLabel('Другое'),
      'Другое, Сюда переходят траты удалённых категорий · удалить нельзя',
    );
    final chevrons = h.inList(
      find.byWidgetPredicate(
        (w) => w is AppIcon && w.icon == AppIcons.chevronRight,
      ),
    );
    expect(chevrons, findsNWidgets(10));
    final otherTop = tester.getTopLeft(h.inList(find.text('Другое'))).dy;
    for (final chevron in chevrons.evaluate()) {
      expect(
        tester.getTopLeft(find.byElementPredicate((e) => e == chevron)).dy,
        lessThan(otherTop),
      );
    }
    expect(
      h.inList(
        find.text(
          'Порядок категорий в сетке «Новой траты» — как в этом списке. '
          'Первые 7 видны сразу, остальные под «Все».',
        ),
      ),
      findsOneWidget,
    );
    expect(
      h.messages(),
      contains(
        matches(
          'categories shown budgetId=${h.fixture.budgetId} count=11 '
          r'editable=10 system=1 after \d+ms$',
        ),
      ),
    );
  });

  testWidgets('«Другое» без действий: не кнопка для TalkBack, тап ничего не '
      'открывает', (tester) async {
    final h = await CategoriesHarness.start(tester);
    await h.openList();

    final other = tester.getSemantics(h.row('Другое'));
    expect(other.flagsCollection.isButton, isFalse);
    expect(other.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
    final cafe = tester.getSemantics(h.row('Кафе'));
    expect(cafe.flagsCollection.isButton, isTrue);

    await tester.ensureVisible(h.row('Другое'));
    await tester.pumpAndSettle();
    await tester.tap(h.inList(find.text('Другое')));
    await tester.pumpAndSettle();
    expect(find.byType(CategoryEditorScreen), findsNothing);
    expect(h.location, AppRoutes.categories);
  });

  testWidgets('тап по «Кафе» открывает редактор /categories/<id> с названием, '
      '«назад» возвращает к списку', (tester) async {
    final h = await CategoriesHarness.start(tester);
    final cafe = await h.named('Кафе');
    await h.openList();

    await h.tapRow('Кафе');

    expect(find.byType(CategoryEditorScreen), findsOneWidget);
    expect(h.location, AppRoutes.categoryOf(cafe.id));
    expect(h.inEditor(find.text('Категория')), findsOneWidget);
    expect(h.inEditor(find.text('Кафе')), findsOneWidget);
    expect(h.deleteButton, findsOneWidget);
    expect(
      h.messages(),
      contains('category row #1 tap id=${cafe.id} → ${AppRoutes.category}'),
    );

    await h.shell.systemBack();
    expect(find.byType(CategoryEditorScreen), findsNothing);
    expect(h.location, AppRoutes.categories);
    expect(
      h.shell.navDebug(),
      contains('category editor closed id=${cafe.id} by back'),
    );
  });

  testWidgets('«+» в шапке открывает «Новую категорию» без «Удалить '
      'категорию»; стрелка назад закрывает', (tester) async {
    final h = await CategoriesHarness.start(tester);
    await h.openList();

    await h.tapAdd();

    expect(h.location, AppRoutes.newCategory);
    expect(h.inEditor(find.text('Новая категория')), findsOneWidget);
    expect(h.deleteButton, findsNothing);
    expect(h.saveButton, findsOneWidget);
    expect(
      h.messages(),
      contains(
        'categories add tap budgetId=${h.fixture.budgetId} → '
        '${AppRoutes.newCategory}',
      ),
    );

    await tester.tap(h.inEditor(find.bySemanticsLabel('Назад')));
    await tester.pumpAndSettle();
    expect(h.location, AppRoutes.categories);
    expect(
      h.shell.navDebug(),
      contains('category editor closed new by back button'),
    );
  });

  testWidgets('на 320 dp со шрифтом 2.0 строки и «+» не меньше 48, подписи '
      'не обрезаны, список прокручивается до подписи', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final h = await CategoriesHarness.start(tester, size: const Size(320, 640));
    await h.openList();

    expect(tester.takeException(), isNull);
    final add = tester.getRect(
      h.inList(find.bySemanticsLabel('Новая категория')),
    );
    expect(add.width, greaterThanOrEqualTo(48));
    expect(add.height, greaterThanOrEqualTo(48));
    for (final (name, _) in mockupCategoryCounts) {
      final rect = tester.getRect(h.row(name));
      expect(rect.height, greaterThanOrEqualTo(48), reason: name);
      expect(rect.width, 296, reason: name);
    }
    final hint = h.inList(find.textContaining('Порядок категорий'));
    await tester.ensureVisible(hint);
    await tester.pumpAndSettle();
    expect(tester.getRect(hint).bottom, lessThanOrEqualTo(640));
    expect(h.messages(Level.SEVERE), isEmpty);
  });
}
