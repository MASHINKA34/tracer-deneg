import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/core/router.dart';
import 'package:milionchik/features/categories/categories_screen.dart';
import 'package:milionchik/features/categories/category_editor_screen.dart';
import 'package:milionchik/features/categories/category_emoji_sheet.dart';
import 'package:milionchik/features/expense/category_grid.dart';
import 'package:milionchik/features/expense/new_expense_screen.dart';
import 'package:milionchik/ui/components/category_tile.dart';
import 'package:milionchik/ui/components/text_field.dart';
import 'package:shared/shared.dart';

import '../expense/new_expense_harness.dart' show tapCategory;
import 'categories_harness.dart';

Finder _emojiField() => find.descendant(
  of: find.byType(CategoryEmojiSheet),
  matching: find.byType(EditableText),
);

String? _nameError(WidgetTester tester) => tester
    .widget<AppTextField>(
      find.descendant(
        of: find.byType(CategoryEditorScreen),
        matching: find.byType(AppTextField),
      ),
    )
    .errorText;

List<String> _gridNames(WidgetTester tester) => [
  for (final tile in tester.widgetList<CategoryTile>(
    find.descendant(
      of: find.byType(NewExpenseScreen),
      matching: find.byType(CategoryTile),
    ),
  ))
    tile.name,
];

Future<void> _pickEmojiFromKeyboard(CategoriesHarness h, String typed) async {
  await h.tapSemantics('Другой эмодзи');
  expect(find.byType(CategoryEmojiSheet), findsOneWidget);
  await h.tester.enterText(_emojiField(), typed);
  await h.tester.pumpAndSettle();
}

void main() {
  testWidgets('создать «🐱 Кот»: «+», название, «➕» и эмодзи с клавиатуры, '
      'бирюзовый, «Сохранить» → в списке перед «Другое», в базе и в «Все»; '
      'info [categories] без названия', (tester) async {
    final h = await CategoriesHarness.start(tester);
    await h.openList();
    await h.tapAdd();

    await h.typeName('Кот');
    await _pickEmojiFromKeyboard(h, '🐱');
    expect(find.byType(CategoryEmojiSheet), findsNothing);
    expect(h.inEditor(find.text('🐱')), findsOneWidget);
    expect(
      tester.widget<EditableText>(h.nameField).focusNode.hasFocus,
      isFalse,
      reason: 'after the emoji sheet the name keyboard must not come back',
    );
    await h.tapSemantics('Бирюзовый');
    await h.tapButton(h.saveButton);

    expect(find.byType(CategoryEditorScreen), findsNothing);
    expect(h.location, AppRoutes.categories);
    final stored = await h.stored();
    expect(stored.map((c) => c.name).toList().sublist(9), [
      'Подарки',
      'Кот',
      'Другое',
    ]);
    final cat = stored[10];
    expect(cat.emoji, '🐱');
    expect(cat.color, CategoryColor.teal);
    expect(h.shownNames(['Подарки', 'Кот', 'Другое']), [
      'Подарки',
      'Кот',
      'Другое',
    ]);
    expect(h.rowLabel('Кот'), 'Кот, 0 трат');

    final info = h.logs(Level.INFO).toList();
    expect(info, hasLength(1));
    expect(
      info.single.message,
      matches(
        'category created id=${cat.id} budgetId=${h.fixture.budgetId} '
        r'order=10 color=teal in \d+ms$',
      ),
    );
    for (final r in h.shell.records) {
      final text = '${r.message} ${r.error}';
      expect(text, isNot(contains('Кот')), reason: text);
    }
    expect(
      h.messages(),
      containsAllInOrder([
        'category editor opened new',
        'category edit new ➕ tap → emoji keyboard sheet',
        'emoji sheet opened: text field with the system keyboard',
        'emoji sheet input length=1 ends with an emoji → applying it and '
            'closing',
        'category edit new emoji set from=keyboard',
        'category edit new color default → teal',
      ]),
    );

    await h.shell.systemBack();
    await h.shell.tapPlus();
    expect(_gridNames(tester), hasLength(8));
    expect(_gridNames(tester), isNot(contains('Кот')));
    await tapCategory(tester, 'Все');
    final all = [
      for (final tile in tester.widgetList<CategoryTile>(
        find.descendant(
          of: find.byType(AllCategoriesSheet),
          matching: find.byType(CategoryTile),
        ),
      ))
        tile.name,
    ];
    expect(all.sublist(all.length - 3), ['Подарки', 'Кот', 'Другое']);
  });

  testWidgets('в бюджете 6 своих категорий: новая «Кот» седьмая — видна в '
      'сетке «Новой траты» перед «Все»', (tester) async {
    final h = await CategoriesHarness.start(tester, mockup: false);
    for (final name in ['Связь', 'Подарки', 'Одежда', 'Развлечения']) {
      final category = await h.named(name);
      await h.write(() => h.fixture.categories.delete(category.id));
    }
    await h.openList();
    await h.tapAdd();
    await h.typeName('Кот');
    await _pickEmojiFromKeyboard(h, '🐱');
    await h.tapButton(h.saveButton);
    await h.shell.systemBack();

    await h.shell.tapPlus();
    expect(_gridNames(tester), [
      'Продукты',
      'Кафе',
      'Транспорт',
      'Дом',
      'Здоровье',
      'Спорт',
      'Кот',
      'Все',
    ]);
  });

  testWidgets('правка «Кафе»: новое название, 🍔 из сетки и синий → в списке '
      '«Кофейни» на том же месте, в базе только изменённое, info с полями', (
    tester,
  ) async {
    final h = await CategoriesHarness.start(tester);
    final cafe = await h.named('Кафе');
    await h.openList();
    await h.tapRow('Кафе');

    await h.typeName('  Кофейни ');
    await h.tapSemantics('🍔');
    await h.tapSemantics('Синий');
    expect(
      tester.getSemantics(h.inEditor(find.bySemanticsLabel('🍔'))),
      isSemantics(isSelected: true),
    );
    await h.tapButton(h.saveButton);

    expect(h.location, AppRoutes.categories);
    final saved = (await h.stored()).singleWhere((c) => c.id == cafe.id);
    expect(saved.name, 'Кофейни');
    expect(saved.emoji, '🍔');
    expect(saved.color, CategoryColor.blue);
    expect(saved.sortOrder, cafe.sortOrder);
    expect(h.rowLabel('Кофейни'), 'Кофейни, 11 трат');
    expect(h.shownNames(['Продукты', 'Кофейни', 'Транспорт']), [
      'Продукты',
      'Кофейни',
      'Транспорт',
    ]);
    expect(h.messages(Level.INFO), [
      matches(
        'category updated id=${cafe.id} budgetId=${h.fixture.budgetId} '
        r'fields=name,emoji,color in \d+ms$',
      ),
    ]);
  });

  testWidgets('«Сохранить» без изменений просто возвращает к списку, в '
      'очередь отправки ничего не пишется', (tester) async {
    final h = await CategoriesHarness.start(tester);
    final outbox = await h.read(
      () => h.shell.db.select(h.shell.db.outbox).get(),
    );
    await h.openList();
    await h.tapRow('Дом');

    await h.tapButton(h.saveButton);

    expect(h.location, AppRoutes.categories);
    expect(
      await h.read(() => h.shell.db.select(h.shell.db.outbox).get()),
      hasLength(outbox.length),
    );
    expect(h.messages(Level.INFO), isEmpty);
    expect(
      h.messages(),
      contains(
        matches(
          r'^category save id=.+: nothing changed → back without writing$',
        ),
      ),
    );
  });

  testWidgets('название: пустое — «Введи название», 25 символов — «Не длиннее '
      '24 символов», «Сохранить» ничего не пишет и экран остаётся', (
    tester,
  ) async {
    final h = await CategoriesHarness.start(tester);
    final cafe = await h.named('Кафе');
    await h.openList();
    await h.tapRow('Кафе');
    expect(_nameError(tester), isNull);

    await h.typeName('');
    expect(_nameError(tester), 'Введи название');
    await h.tapButton(h.saveButton);
    expect(find.byType(CategoryEditorScreen), findsOneWidget);

    await h.typeName('Кафе и рестораны у работы');
    expect('Кафе и рестораны у работы'.length, 25);
    expect(_nameError(tester), 'Не длиннее 24 символов');
    expect(h.inEditor(find.text('Не длиннее 24 символов')), findsOneWidget);
    await h.tapButton(h.saveButton);
    expect(find.byType(CategoryEditorScreen), findsOneWidget);

    await h.typeName('Кафе и рестораны у дома');
    expect(_nameError(tester), isNull);
    expect((await h.stored()).singleWhere((c) => c.id == cafe.id).name, 'Кафе');
    expect(h.messages(Level.INFO), [
      contains('blocked: category_name_empty length=0 max=24'),
      contains('blocked: category_name_too_long length=25 max=24'),
    ]);
  });

  testWidgets('новая категория: «Сохранить» с пустым названием показывает '
      '«Введи название», категория не создаётся', (tester) async {
    final h = await CategoriesHarness.start(tester);
    await h.openList();
    await h.tapAdd();
    expect(_nameError(tester), isNull);

    await h.tapButton(h.saveButton);

    expect(_nameError(tester), 'Введи название');
    expect(find.byType(CategoryEditorScreen), findsOneWidget);
    expect(await h.stored(), hasLength(11));
  });

  testWidgets('«➕»: буква — ошибка «Это не эмодзи», шторка остаётся; закрытие '
      '«назад» оставляет прежний эмодзи', (tester) async {
    final h = await CategoriesHarness.start(tester);
    await h.openList();
    await h.tapRow('Кафе');

    await _pickEmojiFromKeyboard(h, 'к');
    expect(find.byType(CategoryEmojiSheet), findsOneWidget);
    expect(
      find.text('Это не эмодзи — выбери значок на эмодзи-клавиатуре'),
      findsOneWidget,
    );
    await tester.enterText(_emojiField(), '');
    await tester.pump();
    expect(
      find.text('Это не эмодзи — выбери значок на эмодзи-клавиатуре'),
      findsNothing,
    );
    await h.shell.systemBack();

    expect(find.byType(CategoryEmojiSheet), findsNothing);
    expect(find.byType(CategoryEditorScreen), findsOneWidget);
    expect(
      tester.getSemantics(h.inEditor(find.bySemanticsLabel('☕'))),
      isSemantics(isSelected: true),
    );
    expect(
      h.messages(),
      containsAllInOrder([
        'emoji sheet input rejected: emoji_invalid length=1',
        matches(r'^emoji sheet closed without emoji after \d+ms'),
      ]),
    );
  });

  testWidgets('«назад» с несохранённой правкой: в базе прежняя категория, в '
      'debug-логе какие поля отброшены', (tester) async {
    final h = await CategoriesHarness.start(tester);
    final dom = await h.named('Дом');
    await h.openList();
    await h.tapRow('Дом');
    await h.typeName('Квартира');
    await h.tapSemantics('Красный');

    await h.shell.systemBack();

    expect(find.byType(CategoriesScreen), findsOneWidget);
    final stored = (await h.stored()).singleWhere((c) => c.id == dom.id);
    expect(stored.name, 'Дом');
    expect(stored.color, dom.color);
    expect(
      h.messages(),
      contains(
        'category editor id=${dom.id} closed by back with unsaved '
        'fields=name,color → changes discarded',
      ),
    );
  });

  testWidgets('ошибка записи в базу: снекбар, экран и правка остаются, error '
      '[categories] без значений параметров SQL', (tester) async {
    final h = await CategoriesHarness.start(tester);
    final cafe = await h.named('Кафе');
    await h.write(
      () => h.shell.db.customStatement(
        'CREATE TRIGGER categories_fail BEFORE UPDATE ON categories '
        "BEGIN SELECT RAISE(ABORT, 'disk I/O error'); END",
      ),
    );
    await h.openList();
    await h.tapRow('Кафе');
    await h.typeName('Кофейня Барсик');

    await h.tapButton(h.saveButton);

    expect(find.byType(CategoryEditorScreen), findsOneWidget);
    expect(
      find.text('Не удалось сохранить категорию. Попробуй ещё раз'),
      findsOneWidget,
    );
    expect(h.inEditor(find.text('Кофейня Барсик')), findsOneWidget);
    final errors = h.logs(Level.SEVERE).toList();
    expect(errors, hasLength(1));
    expect(
      errors.single.message,
      matches(
        '^category save failed id=${cafe.id} fields=name after '
        r'\d+ms, nothing saved: SqliteException',
      ),
    );
    for (final r in h.shell.records) {
      final text = '${r.message} ${r.error}';
      expect(text, isNot(contains('Барсик')), reason: text);
    }
    expect((await h.stored()).singleWhere((c) => c.id == cafe.id).name, 'Кафе');
  });

  testWidgets('редактор на 320 dp со шрифтом 2.0: плитки эмодзи 48 × 48 без '
      'наложений, кружки цвета 48 в высоту без наложений, кнопки видны '
      'прокруткой', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final h = await CategoriesHarness.start(tester, size: const Size(320, 640));
    await h.openList();
    await h.tapRow('Кафе');
    expect(tester.takeException(), isNull);

    final cells = [
      for (final emoji in [...frequentEmojis, 'Другой эмодзи'])
        tester.getRect(h.inEditor(find.bySemanticsLabel(emoji))),
    ];
    final dots = [
      for (final name in colorNames)
        tester.getRect(h.inEditor(find.bySemanticsLabel(name))),
    ];
    for (final rect in cells) {
      expect(rect.width, greaterThanOrEqualTo(48));
      expect(rect.height, greaterThanOrEqualTo(48));
    }
    for (final rect in dots) {
      expect(rect.height, greaterThanOrEqualTo(48));
    }
    for (final group in [cells, dots]) {
      for (var i = 0; i < group.length; i++) {
        for (var j = i + 1; j < group.length; j++) {
          final overlap = group[i].intersect(group[j]);
          expect(
            overlap.width <= 0.01 || overlap.height <= 0.01,
            isTrue,
            reason: '$i and $j overlap: ${group[i]} ${group[j]}',
          );
        }
      }
    }
    await tester.ensureVisible(h.deleteButton);
    await tester.pumpAndSettle();
    expect(tester.getRect(h.deleteButton).bottom, lessThanOrEqualTo(640));
  });
}

const List<String> frequentEmojis = [
  '☕',
  '🍔',
  '🍕',
  '🍣',
  '🥐',
  '🍺',
  '🛒',
  '🚕',
  '🏠',
  '💊',
  '👕',
  '🎮',
  '🎁',
  '📱',
  '🏋️',
  '✈️',
  '🐾',
  '📚',
  '💇',
];

const List<String> colorNames = [
  'Зелёный',
  'Оранжевый',
  'Жёлтый',
  'Синий',
  'Красный',
  'Фиолетовый',
  'Розовый',
  'Бирюзовый',
  'Индиго',
  'Коралловый',
];
