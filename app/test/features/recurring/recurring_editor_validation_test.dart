import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/features/recurring/recurring_editor_screen.dart';
import 'package:milionchik/ui/components/text_field.dart';
import 'package:milionchik/ui/theme/app_theme.dart';

import 'recurring_editor_harness.dart';

List<String?> _fieldErrors(WidgetTester tester) => [
  for (final field in tester.widgetList<AppTextField>(
    find.descendant(
      of: find.byType(RecurringEditorScreen),
      matching: find.byType(AppTextField),
    ),
  ))
    field.errorText,
];

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testWidgets('новая пустая: ошибок до «Сохранить» нет; «Сохранить» → «Введи '
      'название», «Введи сумму», «Выбери категорию» красным, ничего не '
      'записано, info [recurring] с кодами', (tester) async {
    final h = await RecurringEditorHarness.start(tester);
    await h.openNew();
    expect(_fieldErrors(tester), [null, null]);
    expect(h.rowLabel('Категория'), 'Категория, Не выбрана');

    await h.save();

    expect(find.byType(RecurringEditorScreen), findsOneWidget);
    expect(_fieldErrors(tester), ['Введи название', 'Введи сумму']);
    expect(h.rowLabel('Категория'), 'Категория, Выбери категорию');
    final value = tester.widget<Text>(
      h.inEditor(find.text('Выбери категорию')),
    );
    final context = tester.element(find.byType(RecurringEditorScreen));
    expect(value.style!.color, context.colors.statusDanger);
    expect(await h.rules(), hasLength(5));
    expect(
      h.messages(Level.INFO),
      contains(
        'recurring save new blocked: '
        'recurring_title_empty,amount_empty,category_missing titleLength=0 '
        'max=40, errors shown on the form',
      ),
    );

    await h.typeTitle('Квартплата');
    await h.enterAmount('4500');
    await h.pickCategory('Связь');
    expect(_fieldErrors(tester), [null, null]);
    expect(h.rowLabel('Категория'), 'Категория, Связь');
  });

  testWidgets('название: 41 символ — «Не длиннее 40 символов» сразу, '
      '«Сохранить» не сохраняет; 40 символов и пробелы по краям — '
      'сохраняется обрезанным', (tester) async {
    final h = await RecurringEditorHarness.start(tester);
    await h.openNew();
    await h.enterAmount('100');
    await h.pickCategory('Связь');

    await h.typeTitle('а' * 41);
    expect(_fieldErrors(tester).first, 'Не длиннее 40 символов');
    await h.save();
    expect(find.byType(RecurringEditorScreen), findsOneWidget);
    expect(await h.rules(), hasLength(5));
    expect(
      h.messages(Level.INFO),
      contains(
        'recurring save new blocked: recurring_title_too_long '
        'titleLength=41 max=40, errors shown on the form',
      ),
    );

    await h.typeTitle('  ${'б' * 40}  ');
    expect(_fieldErrors(tester).first, isNull);
    await h.save();
    expect(find.byType(RecurringEditorScreen), findsNothing);
    final rules = await h.rules();
    expect(rules.where((r) => r.title == 'б' * 40), hasLength(1));
  });

  testWidgets('правка: стёрли название — «Введи название» сразу, '
      '«Сохранить» не меняет правило', (tester) async {
    final h = await RecurringEditorHarness.start(tester);
    final gym = h.budget.rules[gymTitle]!;
    await h.openRule(gymTitle);
    expect(_fieldErrors(tester), [null, null]);

    await h.typeTitle('   ');
    expect(_fieldErrors(tester).first, 'Введи название');
    await h.save();

    expect(find.byType(RecurringEditorScreen), findsOneWidget);
    final rule = (await h.rules()).singleWhere((r) => r.id == gym.id);
    expect(rule.title, gymTitle);
    expect(rule.updatedAt, gym.updatedAt);
  });
}
