import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/core/router.dart';
import 'package:milionchik/features/recurring/recurring_editor_screen.dart';
import 'package:milionchik/features/recurring/recurring_screen.dart';
import 'package:milionchik/ui/components/button.dart';
import 'package:milionchik/ui/components/dialog.dart';
import 'package:shared/shared.dart';

import 'recurring_editor_harness.dart';
import 'recurring_fixture.dart';

Finder _inDialog(Finder finder) =>
    find.descendant(of: find.byType(AppDialog), matching: finder);

Future<void> _openDelete(RecurringEditorHarness h, String title) async {
  await h.openRule(title);
  await h.tapButton(h.deleteButton);
  expect(find.byType(AppDialog), findsOneWidget);
}

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testWidgets('«Удалить регулярную трату» спортзала: диалог «Уже созданные '
      'траты останутся», «Удалить» → назад к списку, правило удалено, '
      'октябрьская трата 2 900 ₽ осталась; info [recurring] с id, днём и мс '
      'без названия', (tester) async {
    final h = await RecurringEditorHarness.start(tester);
    final gym = h.budget.rules[gymTitle]!;
    final before = await h.expensesOf(gym.id);
    expect(before, hasLength(1));

    await _openDelete(h, gymTitle);

    expect(_inDialog(find.text('Удалить регулярную трату?')), findsOneWidget);
    expect(
      _inDialog(
        find.text(
          'Новые траты «Спортзал «Территория»» больше не появятся. Уже '
          'созданные траты останутся в календаре.',
        ),
      ),
      findsOneWidget,
    );
    expect(_inDialog(find.widgetWithText(AppButton, 'Отмена')), findsOneWidget);

    await tester.tap(_inDialog(find.widgetWithText(AppButton, 'Удалить')));
    await tester.pumpAndSettle();

    expect(find.byType(AppDialog), findsNothing);
    expect(find.byType(RecurringEditorScreen), findsNothing);
    expect(find.byType(RecurringScreen), findsOneWidget);
    expect(h.location, AppRoutes.recurring);
    expect(find.text(gymTitle), findsNothing);
    expect((await h.rules()).map((r) => r.id), isNot(contains(gym.id)));
    final tombstone = await h.ruleWithDeleted(gym.id);
    expect(tombstone!.isDeleted, isTrue);
    final after = await h.expensesOf(gym.id);
    expect(after.map((e) => e.id), before.map((e) => e.id));
    expect(after.single.deletedAt, isNull);
    expect(after.single.amount, Money.rubles(2900));
    expect(after.single.spentOn, LocalDate(2026, 10, 12));

    final info = h.messages(Level.INFO).toList();
    expect(
      info,
      contains(
        matches(
          '^recurring rule deleted id=${gym.id} budgetId=${h.budget.id} '
          r'day=12 from=2026-10 in \d+ms, created expenses stay, no new ones$',
        ),
      ),
    );
    expect(
      h.messages(),
      contains('recurring delete tap id=${gym.id} → confirm dialog'),
    );
    expect(
      h.shell.navDebug(),
      contains('recurring editor closed id=${gym.id} by delete'),
    );
    for (final r in h.shell.records.where((r) => r.level >= Level.INFO)) {
      expect(r.message, isNot(contains('Спортзал')), reason: r.message);
      expect(r.message, isNot(contains('2900')), reason: r.message);
    }
  });

  testWidgets('удалённое правило больше не создаёт трат: генератор на 13 '
      'ноября не создаёт ноябрьскую трату спортзала', (tester) async {
    final h = await RecurringEditorHarness.start(tester);
    final gym = h.budget.rules[gymTitle]!;
    await _openDelete(h, gymTitle);
    await tester.tap(_inDialog(find.widgetWithText(AppButton, 'Удалить')));
    await tester.pumpAndSettle();

    final run = await h.read(
      () => seedClockRun(h.shell.db, DateTime(2026, 11, 13, 9)),
    );

    expect(run.ok, isTrue);
    final expenses = await h.expensesOf(gym.id);
    expect(expenses.map((e) => e.recurringMonth), [october]);
  });

  testWidgets('«Отмена» и «назад» в диалоге ничего не удаляют, редактор '
      'остаётся', (tester) async {
    final h = await RecurringEditorHarness.start(tester);
    final gym = h.budget.rules[gymTitle]!;
    await _openDelete(h, gymTitle);

    await tester.tap(_inDialog(find.widgetWithText(AppButton, 'Отмена')));
    await tester.pumpAndSettle();
    expect(find.byType(AppDialog), findsNothing);
    expect(find.byType(RecurringEditorScreen), findsOneWidget);

    await h.tapButton(h.deleteButton);
    await h.shell.systemBack();
    expect(find.byType(AppDialog), findsNothing);
    expect(find.byType(RecurringEditorScreen), findsOneWidget);

    expect((await h.rules()).map((r) => r.id), contains(gym.id));
    expect(
      h.messages(),
      containsAllInOrder([
        'recurring delete id=${gym.id} dialog → cancel: nothing deleted',
        'recurring delete id=${gym.id} dialog dismissed: nothing deleted',
      ]),
    );
    expect(
      h.messages(Level.INFO),
      isNot(contains(startsWith('recurring rule'))),
    );
  });

  testWidgets('у новой регулярной траты нет кнопки удаления и подписи про '
      'созданные траты', (tester) async {
    final h = await RecurringEditorHarness.start(tester);
    await h.openNew();

    expect(h.deleteButton, findsNothing);
    expect(
      h.inEditor(find.text('Уже созданные траты останутся в календаре.')),
      findsNothing,
    );
  });

  testWidgets('у существующей — подпись «Уже созданные траты останутся в '
      'календаре.» под кнопкой удаления', (tester) async {
    final h = await RecurringEditorHarness.start(tester);
    await h.openRule(gymTitle);

    final hint = h.inEditor(
      find.text('Уже созданные траты останутся в календаре.'),
    );
    expect(hint, findsOneWidget);
    expect(
      tester.getTopLeft(hint).dy,
      greaterThan(tester.getBottomLeft(h.deleteButton).dy),
    );
  });
}
