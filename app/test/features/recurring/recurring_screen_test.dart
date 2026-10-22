import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milionchik/features/recurring/recurring_editor_screen.dart';
import 'package:milionchik/features/recurring/recurring_screen.dart';
import 'package:milionchik/ui/components/expense_row.dart';
import 'package:milionchik/ui/icons/app_icon.dart';
import 'package:milionchik/ui/theme/app_theme.dart';
import 'package:shared/shared.dart';

import '../../support/app_scope.dart';
import '../../support/test_fonts.dart';
import '../shell/shell_harness.dart';
import 'recurring_fixture.dart';

String _rub(String digits) => '${digits.replaceAll(' ', nbsp)}$nbsp₽';

List<String> _rows(WidgetTester tester) => [
  for (final row in tester.widgetList<ExpenseRow>(find.byType(ExpenseRow)))
    '${row.emoji} ${row.title} | ${row.subtitle} | '
        '${row.amount.replaceAll(nbsp, ' ')}',
];

Future<(ShellHarness, RecurringBudget)> _openMockup(WidgetTester tester) async {
  await loadTestFonts();
  final db = openTestDatabase();
  final budget = (await tester.runAsync(() => seedRecurringMockup(db)))!;
  final h = await ShellHarness.start(tester, db: db);
  await h.tapTab('Регулярные');
  return (h, budget);
}

Finder _headerPlus() => find.descendant(
  of: find.byType(RecurringScreen),
  matching: find.byWidgetPredicate(
    (w) => w is AppIcon && w.icon == AppIcons.plus,
  ),
);

String _location(WidgetTester tester) => GoRouter.of(
  tester.element(find.byType(RecurringScreen, skipOffstage: false)),
).state.uri.toString();

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testWidgets('данные макета 12:1047 на 19 октября: «Каждый месяц 4 498 ₽», '
      '«5 платежей», «Скоро» 498 ₽ с двумя правилами, «Уже списано в '
      'октябре» 4 000 ₽ с тремя, даты зелёным', (tester) async {
    final (h, _) = await _openMockup(tester);

    expect(h.activeTab.name, 'recurring');
    expect(find.text('Регулярные'), findsWidgets);
    expect(find.text('Каждый месяц'), findsOneWidget);
    expect(find.text(_rub('4 498')), findsOneWidget);
    expect(
      find.text('5 платежей. Сами появляются в календаре в день списания'),
      findsOneWidget,
    );
    expect(find.text('Скоро'), findsOneWidget);
    expect(find.text(_rub('498')), findsOneWidget);
    expect(find.text('Уже списано в октябре'), findsOneWidget);
    expect(find.text(_rub('4 000')), findsOneWidget);
    expect(_rows(tester), [
      '🎵 Музыка | каждое 24-е · через 5 дней | 199 ₽',
      '🎬 Онлайн-кино | каждое 28-е · через 9 дней | 299 ₽',
      '🌐 Домашний интернет | ✓ 3 октября | 650 ₽',
      '📱 Мобильная связь | ✓ 7 октября | 450 ₽',
      '🏋️ Спортзал «Территория» | ✓ 12 октября | 2 900 ₽',
    ]);

    final context = tester.element(find.byType(RecurringScreen));
    final success = context.colors.statusSuccess;
    expect(
      [
        for (final row in tester.widgetList<ExpenseRow>(
          find.byType(ExpenseRow),
        ))
          row.subtitleColor,
      ],
      [null, null, success, success, success],
    );
    expect(_headerPlus(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('«+» в шапке и тап по правилу открывают редактор '
      'поверх меню, «назад» возвращает на вкладку', (tester) async {
    final (h, budget) = await _openMockup(tester);

    await tester.tap(find.bySemanticsLabel('Добавить регулярную трату'));
    await tester.pumpAndSettle();
    expect(find.byType(RecurringEditorScreen), findsOneWidget);
    expect(find.text('Новая регулярная трата'), findsOneWidget);
    expect(
      tester
          .widget<RecurringEditorScreen>(find.byType(RecurringEditorScreen))
          .ruleId,
      isNull,
    );
    await h.systemBack();
    expect(find.byType(RecurringEditorScreen), findsNothing);
    expect(find.byType(RecurringScreen), findsOneWidget);
    expect(_location(tester), '/recurring');

    await tester.tap(find.text('Спортзал «Территория»'));
    await tester.pumpAndSettle();
    final gym = budget.rules['Спортзал «Территория»']!;
    expect(
      tester
          .widget<RecurringEditorScreen>(find.byType(RecurringEditorScreen))
          .ruleId,
      gym.id,
    );
    await tester.tap(find.bySemanticsLabel('Назад'));
    await tester.pumpAndSettle();
    expect(find.byType(RecurringEditorScreen), findsNothing);

    await tester.tap(find.text('Музыка'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<RecurringEditorScreen>(find.byType(RecurringEditorScreen))
          .ruleId,
      budget.rules['Музыка']!.id,
    );
  });

  testWidgets('правил нет — 47:5951: заголовок, пояснение и кнопка, «+» в '
      'шапке нет; кнопка открывает редактор', (tester) async {
    await loadTestFonts();
    final db = openTestDatabase();
    await tester.runAsync(() => seedRecurringBudget(db));
    final h = await ShellHarness.start(tester, db: db);
    await h.tapTab('Регулярные');

    expect(find.text('Пока нет регулярных трат'), findsOneWidget);
    expect(
      find.text(
        'Добавь подписки, аренду, связь — они будут появляться в календаре '
        'сами в нужный день.',
      ),
      findsOneWidget,
    );
    expect(find.byType(ExpenseRow), findsNothing);
    expect(find.text('Каждый месяц'), findsNothing);
    expect(_headerPlus(), findsNothing);

    await tester.tap(find.text('Добавить регулярную трату'));
    await tester.pumpAndSettle();
    expect(find.byType(RecurringEditorScreen), findsOneWidget);
    expect(
      tester
          .widget<RecurringEditorScreen>(find.byType(RecurringEditorScreen))
          .ruleId,
      isNull,
    );
  });

  testWidgets('трату спортзала удалили — правило уходит в «Скоро» на 12 '
      'ноября (через 24 дня), суммы разделов пересчитаны, итог прежний; '
      'новое правило — «6 платежей»', (tester) async {
    final (_, budget) = await _openMockup(tester);
    final gym = budget.rules['Спортзал «Территория»']!;

    await writeWhileShown(
      tester,
      () => budget.expenses.delete(recurringExpenseId(gym.id, october)),
    );

    expect(find.text(_rub('4 498')), findsOneWidget);
    expect(find.text(_rub('3 398')), findsOneWidget);
    expect(find.text(_rub('1 100')), findsOneWidget);
    expect(_rows(tester), [
      '🎵 Музыка | каждое 24-е · через 5 дней | 199 ₽',
      '🎬 Онлайн-кино | каждое 28-е · через 9 дней | 299 ₽',
      '🏋️ Спортзал «Территория» | каждое 12-е · через 24 дня | 2 900 ₽',
      '🌐 Домашний интернет | ✓ 3 октября | 650 ₽',
      '📱 Мобильная связь | ✓ 7 октября | 450 ₽',
    ]);

    await writeWhileShown(
      tester,
      () => budget.rule('Облако', category: 'Связь', rubles: 149, day: 20),
    );

    expect(
      find.text('6 платежей. Сами появляются в календаре в день списания'),
      findsOneWidget,
    );
    expect(find.text(_rub('4 647')), findsOneWidget);
    expect(
      _rows(tester).first,
      '📱 Облако | каждое 20-е · через 1 день | 149 ₽',
    );
  });

  testWidgets('TalkBack: карточка, заголовки разделов и строки — суммы '
      'словами, вместо «✓» — «списано»', (tester) async {
    final handle = tester.ensureSemantics();
    await _openMockup(tester);

    expect(
      find.bySemanticsLabel(
        'Каждый месяц 4${nbsp}498 рублей. 5 платежей. Сами появляются в календаре '
        'в день списания',
      ),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Скоро, 498 рублей'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Уже списано в октябре, 4${nbsp}000 рублей'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Музыка, каждое 24-е, через 5 дней, 199 рублей'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(
        'Спортзал «Территория», списано 12 октября, 2${nbsp}900 рублей',
      ),
      findsOneWidget,
    );
    handle.dispose();
  });
}
