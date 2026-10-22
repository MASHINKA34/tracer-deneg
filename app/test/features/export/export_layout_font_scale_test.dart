import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milionchik/features/export/export_budget_sheet.dart';
import 'package:milionchik/features/export/export_screen.dart';
import 'package:milionchik/ui/components/chip.dart';

import '../../support/test_fonts.dart';
import 'export_fixture.dart';

Finder _inExport(Finder finder) =>
    find.descendant(of: find.byType(ExportScreen), matching: finder);

Rect _visual(WidgetTester tester, Finder owner) => tester.getRect(
  find.descendant(of: owner, matching: find.byType(Material)).first,
);

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testWidgets('360 dp, шрифт 1.0: раскладка как 46:5585 — бюджет 16/64 '
      '328×44, чипы с 152 высотой 36, карточка файла 16/202 328×72, кнопка '
      '16/350 328×52', (tester) async {
    await loadTestFonts();
    await ExportHarness.open(tester);

    expect(
      _visual(tester, find.byType(ExportBudgetRow)),
      const Rect.fromLTWH(16, 64, 328, 44),
    );
    final chips = _inExport(find.byType(AppChip));
    expect(chips, findsNWidgets(3));
    for (var i = 0; i < 3; i++) {
      final rect = _visual(tester, chips.at(i));
      expect(rect.top, 152, reason: 'chip $i');
      expect(rect.height, 36, reason: 'chip $i');
    }
    expect(_visual(tester, chips.at(0)).left, 16);
    expect(
      _visual(tester, chips.at(1)).left,
      _visual(tester, chips.at(0)).right + 8,
    );
    expect(
      tester.getRect(find.byType(ExportFileCard)),
      const Rect.fromLTWH(16, 202, 328, 72),
    );
    expect(
      tester.getRect(_inExport(find.byType(TextButton))),
      const Rect.fromLTWH(16, 350, 328, 52),
    );
  });

  for (final width in const [320.0, 360.0]) {
    for (final scale in const [1.0, 2.0]) {
      testWidgets('${width.toInt()} dp, шрифт $scale: ничего не обрезано, '
          'области бюджета, чипов и кнопки не меньше 48 и не налезают, '
          'нажатие у верхнего края строки бюджета открывает шторку', (
        tester,
      ) async {
        await loadTestFonts();
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearAllTestValues);
        final h = await ExportHarness.open(tester, size: Size(width, 800));
        expect(tester.takeException(), isNull);

        final budget = tester.getRect(find.byType(ExportBudgetRow));
        expect(budget.height, greaterThanOrEqualTo(48));
        expect(budget.width, width - 32);
        final targets = <Rect>[
          budget,
          for (final chip in tester.widgetList(_inExport(find.byType(AppChip))))
            tester.getRect(find.byWidget(chip)),
        ];
        for (final rect in targets.skip(1)) {
          expect(rect.height, greaterThanOrEqualTo(48));
          expect(rect.right, lessThanOrEqualTo(width - 16));
        }
        for (var i = 0; i < targets.length; i++) {
          for (var j = i + 1; j < targets.length; j++) {
            final overlap = targets[i].intersect(targets[j]);
            expect(
              overlap.width <= 0 || overlap.height <= 0,
              isTrue,
              reason: 'targets $i and $j overlap: $overlap',
            );
          }
        }
        final button = _inExport(find.byType(TextButton));
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        expect(tester.getSize(button).height, greaterThanOrEqualTo(52));

        await tester.ensureVisible(find.byType(ExportBudgetRow));
        await tester.pumpAndSettle();
        final row = tester.getRect(find.byType(ExportBudgetRow));
        await tester.tapAt(Offset(row.center.dx, row.top + 1));
        await h.settle();
        expect(find.byType(ExportBudgetSheet), findsOneWidget);
      });
    }
  }
}
