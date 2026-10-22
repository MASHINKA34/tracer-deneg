import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/core/router.dart';
import 'package:milionchik/features/expense/edit_expense_screen.dart';
import 'package:milionchik/features/search/search_screen.dart';
import 'package:milionchik/ui/components/expense_row.dart';
import 'package:milionchik/ui/components/snackbar.dart';

import '../../support/app_scope.dart';
import 'search_fixture.dart';

Finder _row(String amount) => inSearch(
  find.byWidgetPredicate(
    (w) => w is ExpenseRow && w.amount.replaceAll(' ', ' ') == amount,
  ),
);

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testWidgets('тап по результату открывает правку траты, «назад» — снова '
      'поиск с тем же запросом', (tester) async {
    final db = openTestDatabase();
    final seed = (await tester.runAsync(() => seedSearchMockup(db)))!;
    final h = await openSearch(tester, seed: (_) async {}, database: db);
    await typeQuery(tester, 'кофе');

    await tester.tap(_row('340 ₽'));
    await settleSearch(tester);

    expect(find.byType(EditExpenseScreen), findsOneWidget);
    final uri = GoRouter.of(tester.element(find.byType(EditExpenseScreen)))
        .state
        .uri;
    expect(uri.path, AppRoutes.expenseOf(seed.expenseIds['круассан']!));
    expect(
      searchDebugLogs(h),
      contains(
        'search result tap id=${seed.expenseIds['круассан']} → /expense/:id',
      ),
    );

    await h.systemBack();
    await settleSearch(tester);
    expect(find.byType(SearchScreen), findsOneWidget);
    expect(find.text('кофе'), findsOneWidget);
    expect(shownAmounts(tester), hasLength(5));
  });

  testWidgets('смахивание результата удаляет трату со снекбаром «Отменить», '
      'итог пересчитан; «Отменить» возвращает её', (tester) async {
    final db = openTestDatabase();
    final seed = (await tester.runAsync(() => seedSearchMockup(db)))!;
    final h = await openSearch(tester, seed: (_) async {}, database: db);
    await typeQuery(tester, 'кофе');

    await tester.drag(_row('560 ₽'), const Offset(-300, 0));
    await settleSearch(tester);

    expect(_row('560 ₽'), findsNothing);
    expect(foundLine(tester), 'Найдено 4 траты · 910 ₽');
    expect(find.byType(AppSnackbar), findsOneWidget);
    expect(
      [
        for (final r in h.records)
          if (r.loggerName == 'expense' && r.level == Level.INFO) r.message,
      ],
      contains(
        matches(
          '^expense deleted id=${seed.expenseIds['зёрна']} '
          'budgetId=${seed.budgetId} from=search swipe in '
          r'\d+ms, undo snackbar for 5s$',
        ),
      ),
    );

    await tester.tap(
      find.descendant(
        of: find.byType(AppSnackbar),
        matching: find.text('Отменить'),
      ),
    );
    await settleSearch(tester);

    expect(_row('560 ₽'), findsOneWidget);
    expect(foundLine(tester), 'Найдено 5 трат · 1 470 ₽');
  });
}
