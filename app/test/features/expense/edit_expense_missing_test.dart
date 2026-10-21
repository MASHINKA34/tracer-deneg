import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/features/expense/edit_expense_screen.dart';
import 'package:milionchik/features/month/day_sheet.dart';
import 'package:milionchik/features/month/month_screen.dart';
import 'package:milionchik/ui/components/bottom_nav.dart';

import 'edit_expense_harness.dart';

String _location(WidgetTester tester) =>
    GoRouter.of(tester.element(find.byType(AppBottomNav, skipOffstage: false)))
        .state
        .uri
        .toString();

void main() {
  testWidgets('несуществующая трата: «Трата не найдена» с пояснением, без '
      'полей и корзины, «Назад» возвращает на главную, warn в логе', (
    tester,
  ) async {
    final h = await EditHarness.start(tester);
    await h.openById('no-such-expense');

    expect(find.byType(EditExpenseScreen), findsOneWidget);
    expect(h.inEdit(find.text('Трата не найдена')), findsOneWidget);
    expect(
      h.inEdit(
        find.text('Возможно, её удалили — здесь или на другом телефоне.'),
      ),
      findsOneWidget,
    );
    expect(h.inEdit(find.text('Сохранить')), findsNothing);
    expect(h.inEdit(find.text('Удалить трату')), findsNothing);
    expect(h.inEdit(find.bySemanticsLabel('Удалить трату')), findsNothing);
    expect(
      h.shell.records
          .where((r) => r.loggerName == 'expense' && r.level >= Level.WARNING)
          .map((r) => '${r.level.name} ${r.message}'),
      [
        'WARNING expense edit id=no-such-expense: expense is not found or '
            'deleted → not found screen',
      ],
    );

    await tester.tap(h.inEdit(find.text('Назад')));
    await tester.pumpAndSettle();
    expect(find.byType(EditExpenseScreen), findsNothing);
    expect(find.byType(MonthScreen), findsOneWidget);
    expect(_location(tester), '/month');
  });

  testWidgets('удалённая трата (надгробие) открывается экраном «Трата не '
      'найдена», стрелка назад — к шторке дня', (tester) async {
    final h = await EditHarness.start(tester);
    await h.openDay('19 октября');
    final target = (await h.day(october19))
        .firstWhere((e) => e.id != h.pyaterochka.id);
    await h.deleteWhileShown(target.id);
    await h.openById(target.id);

    expect(h.inEdit(find.text('Трата не найдена')), findsOneWidget);
    await tester.tap(h.inEdit(find.bySemanticsLabel('Назад')).first);
    await tester.pumpAndSettle();
    expect(find.byType(EditExpenseScreen), findsNothing);
    expect(find.byType(DaySheet), findsOneWidget);
  });

  testWidgets('трату удалили, пока открыт экран правки: сразу «Трата не '
      'найдена», «Сохранить» нет, info в логе', (tester) async {
    final h = await EditHarness.start(tester);
    await h.openById(h.pyaterochka.id);
    await h.typeAmount('<<<99');
    expect(h.saveEnabled, isTrue);

    await h.deleteWhileShown(h.pyaterochka.id);

    expect(h.inEdit(find.text('Трата не найдена')), findsOneWidget);
    expect(h.inEdit(find.text('Сохранить')), findsNothing);
    expect(
      h.shell.records
          .where((r) => r.loggerName == 'expense' && r.level == Level.INFO)
          .map((r) => r.message),
      contains(
        'expense edit id=${h.pyaterochka.id}: expense was deleted while the '
        'screen was open → not found screen',
      ),
    );
    expect(
      h.shell.records.where(
        (r) => r.loggerName == 'expense' && r.level >= Level.WARNING,
      ),
      isEmpty,
    );
  });

  testWidgets('ошибка чтения траты из базы: «Не удалось открыть трату», '
      'error [expense] без параметров SQL', (tester) async {
    final h = await EditHarness.start(tester);
    await tester.runAsync(
      () => h.db.customStatement('ALTER TABLE expenses RENAME TO expenses_x'),
    );
    await h.openById(h.pyaterochka.id);

    expect(h.inEdit(find.text('Не удалось открыть трату')), findsOneWidget);
    expect(
      h.inEdit(find.text('Вернись назад и попробуй ещё раз.')),
      findsOneWidget,
    );
    final errors = [
      for (final r in h.shell.records)
        if (r.loggerName == 'expense' && r.level == Level.SEVERE) r,
    ];
    expect(errors, hasLength(1));
    expect(
      errors.single.message,
      matches(
        '^expense edit id=${h.pyaterochka.id}: reading the expense failed '
        r'after \d+ms → error screen: SqliteException',
      ),
    );
    expect(errors.single.message, contains('no such table: expenses'));
    expect(errors.single.stackTrace, isNotNull);
    await tester.runAsync(
      () => h.db.customStatement('ALTER TABLE expenses_x RENAME TO expenses'),
    );
  });
}
