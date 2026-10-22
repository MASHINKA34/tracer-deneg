import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/features/export/export_screen.dart';
import 'package:milionchik/features/shell/tab_stub_screen.dart';
import 'package:milionchik/ui/components/bottom_nav.dart';
import 'package:milionchik/ui/components/list_row.dart';

import 'export_fixture.dart';

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testWidgets('строка «Экспорт трат в CSV» на заглушке профиля открывает '
      'экспорт, «назад» возвращает в профиль', (tester) async {
    final h = await ExportHarness.open(tester, push: false);

    await tester.tap(
      find.descendant(
        of: find.byType(AppBottomNav),
        matching: find.text('Профиль'),
      ),
    );
    await h.settle();
    final row = find.widgetWithText(ListRow, 'Экспорт трат в CSV');
    expect(row, findsOneWidget);
    expect(tester.getSize(row).height, greaterThanOrEqualTo(48));

    await tester.tap(row);
    await h.settle();

    expect(find.byType(ExportScreen), findsOneWidget);
    expect(find.text('Экспорт трат'), findsOneWidget);
    expect(
      h.exportLogs(Level.FINE).map((r) => r.message),
      contains('profile export row tap → /export'),
    );

    await tester.tap(find.bySemanticsLabel('Назад'));
    await h.settle();

    expect(find.byType(ExportScreen), findsNothing);
    expect(find.byType(TabStubScreen), findsOneWidget);
    expect(row, findsOneWidget);
    expect(
      h.records.where((r) => r.loggerName == 'nav').map((r) => r.message),
      contains('export closed by back button'),
    );
  });
}
