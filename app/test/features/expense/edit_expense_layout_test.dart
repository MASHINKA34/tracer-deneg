import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milionchik/features/expense/expense_comment_sheet.dart';
import 'package:milionchik/features/expense/expense_date_sheet.dart';
import 'package:milionchik/ui/components/button.dart';
import 'package:milionchik/ui/components/snackbar.dart';

import '../../support/test_fonts.dart';
import 'edit_expense_harness.dart';

Rect _rect(WidgetTester tester, Finder finder) => tester.getRect(finder);

void main() {
  testWidgets('360 × 800, статус-бар 32, шрифт 1.0: поля, подписи и кнопки '
      'на местах 43:4368; области нажатия категории, даты и комментария не '
      'меньше 48 и не заходят друг на друга', (tester) async {
    await loadTestFonts();
    final h = await EditHarness.start(tester, topInset: 32);
    await h.openById(h.pyaterochka.id);

    expect(
      tester.getTopLeft(h.inEdit(find.text('Трата'))),
      const Offset(54, 48),
    );
    expect(tester.getTopLeft(h.inEdit(find.text('Сумма'))).dy, 108);
    expect(tester.getTopLeft(h.inEdit(find.text('640'))).dy, 126);
    expect(
      tester.getTopLeft(h.inEdit(find.text('Категория'))),
      const Offset(30, 246),
    );
    expect(
      tester.getTopLeft(h.inEdit(find.text('Дата'))),
      const Offset(30, 300),
    );
    expect(
      tester.getTopLeft(h.inEdit(find.text('Комментарий'))),
      const Offset(30, 344),
    );
    expect(
      tester.getTopLeft(h.inEdit(find.text('Бюджет'))),
      const Offset(30, 388),
    );
    expect(
      tester.getTopRight(h.inEdit(find.text('Пятёрочка'))),
      const Offset(302, 345),
    );

    expect(
      _rect(tester, h.row('Категория')),
      const Rect.fromLTRB(16, 224, 344, 286),
    );
    expect(
      _rect(tester, h.row('Дата')),
      const Rect.fromLTRB(16, 286, 344, 334),
    );
    expect(
      _rect(tester, h.row('Комментарий')),
      const Rect.fromLTRB(16, 334, 344, 382),
    );
    expect(
      _rect(tester, h.row('Бюджет')),
      const Rect.fromLTRB(16, 382, 344, 420),
    );
    expect(
      tester.getSemantics(h.row('Бюджет')).flagsCollection.isButton,
      isFalse,
    );

    final save = _rect(tester, h.saveButton);
    expect(save, const Rect.fromLTWH(16, 488, 328, 52));
    expect(
      _rect(tester, h.inEdit(find.widgetWithText(AppButton, 'Удалить трату'))),
      const Rect.fromLTWH(16, 556, 328, 52),
    );
    expect(
      _rect(tester, h.inEdit(find.bySemanticsLabel('Назад'))),
      const Rect.fromLTWH(4, 36, 48, 48),
    );
    expect(
      _rect(tester, h.inEdit(find.bySemanticsLabel('Удалить трату')).first),
      const Rect.fromLTWH(308, 36, 48, 48),
    );
  });

  for (final width in const [360.0, 320.0]) {
    for (final scale in const [1.0, 2.0]) {
      testWidgets('$width dp, шрифт $scale: без переполнений, всё нажимается '
          'и прокручивается до «Удалить трату», края строк даты и '
          'комментария открывают свою шторку', (tester) async {
        await loadTestFonts();
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearAllTestValues);
        final h = await EditHarness.start(
          tester,
          size: Size(width, 800),
          topInset: 24,
          bottomInset: 24,
        );
        await h.openById(h.pyaterochka.id);
        expect(tester.takeException(), isNull);

        final rows = [
          for (final label in ['Категория', 'Дата', 'Комментарий', 'Бюджет'])
            _rect(tester, h.row(label)),
        ];
        for (var i = 0; i < 3; i++) {
          expect(rows[i].height, greaterThanOrEqualTo(48), reason: '$i');
          expect(rows[i].bottom, lessThanOrEqualTo(rows[i + 1].top));
          expect(rows[i].width, width - 32);
        }
        final back = _rect(tester, h.inEdit(find.bySemanticsLabel('Назад')));
        final trash = _rect(
          tester,
          h.inEdit(find.bySemanticsLabel('Удалить трату')).first,
        );
        expect(back.size, const Size(48, 48));
        expect(trash.size, const Size(48, 48));
        expect(trash.right, lessThanOrEqualTo(width));
        expect(
          _rect(tester, h.inEdit(find.text('Трата'))).right,
          lessThanOrEqualTo(trash.left),
        );

        for (final (label, sheet) in [
          ('Дата', ExpenseDateSheet),
          ('Комментарий', ExpenseCommentSheet),
        ]) {
          for (final edge in [2.0, -2.0]) {
            await tester.ensureVisible(h.row(label));
            await tester.pumpAndSettle();
            final rect = _rect(tester, h.row(label));
            await tester.tapAt(
              Offset(
                rect.center.dx,
                edge > 0 ? rect.top + edge : rect.bottom + edge,
              ),
            );
            await tester.pumpAndSettle();
            expect(find.byType(sheet), findsOneWidget, reason: '$label $edge');
            expect(tester.takeException(), isNull);
            await h.shell.systemBack();
            expect(find.byType(sheet), findsNothing);
          }
        }

        final delete = h.inEdit(
          find.widgetWithText(AppButton, 'Удалить трату'),
        );
        await tester.ensureVisible(delete);
        await tester.pumpAndSettle();
        expect(_rect(tester, delete).bottom, lessThanOrEqualTo(800 - 24));
        await tester.tap(delete);
        await tester.pumpAndSettle();
        expect(find.byType(AppSnackbar), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
