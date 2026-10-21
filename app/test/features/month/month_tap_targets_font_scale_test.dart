import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milionchik/features/month/month_header.dart';
import 'package:milionchik/features/month/month_picker_sheet.dart';
import 'package:milionchik/features/shell/search_stub_screen.dart';
import 'package:milionchik/ui/components/bottom_nav.dart';

import '../../support/app_scope.dart';
import '../../support/test_fonts.dart';
import '../shell/shell_harness.dart';
import 'month_fixture.dart';

const String _budgetName = 'Личный бюджет';

Finder _header(String label) => find.descendant(
  of: find.byType(MonthHeader),
  matching: find.bySemanticsLabel(label),
);

Finder _inPicker(Finder finder) =>
    find.descendant(of: find.byType(MonthPicker), matching: finder);

void _expectTapTarget(WidgetTester tester, Finder finder, String what) {
  final size = tester.getSize(finder);
  expect(size.width, greaterThanOrEqualTo(48), reason: '$what: $size');
  expect(size.height, greaterThanOrEqualTo(48), reason: '$what: $size');
}

Future<void> _tapAt(WidgetTester tester, Offset position) async {
  await tester.tapAt(position);
  await tester.pumpAndSettle();
}

List<String> _truncatedTexts(WidgetTester tester, double width) {
  final problems = <String>{};
  for (final paragraph
      in tester.allRenderObjects.whereType<RenderParagraph>().toSet()) {
    if (!paragraph.attached || !paragraph.hasSize) continue;
    final text = paragraph.text.toPlainText();
    final rect = MatrixUtils.transformRect(
      paragraph.getTransformTo(null),
      Offset.zero & paragraph.size,
    );
    if (paragraph.didExceedMaxLines && text != _budgetName) {
      problems.add('«$text» cut by maxLines');
    }
    if (rect.left < -0.5 || rect.right > width + 0.5) {
      problems.add('«$text» outside the screen: $rect');
    }
  }
  return problems.toList();
}

void main() {
  for (final width in const [360.0, 320.0]) {
    for (final scale in const [1.0, 2.0]) {
      testWidgets('${width.toInt()} dp, шрифт $scale: поиск, аватар, ‹ › '
          'карточки и ‹ › года — не меньше 48 × 48 и нажимаются у краёв '
          'области, текст главной, выбора месяца и шторки дня не обрезан', (
        tester,
      ) async {
        await loadTestFonts();
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearAllTestValues);
        final db = openTestDatabase();
        await tester.runAsync(() => seedMockupOctober(db));
        final h = await ShellHarness.start(
          tester,
          db: db,
          size: Size(width, 800),
        );

        expect(_truncatedTexts(tester, width), isEmpty);

        final search = _header('Поиск');
        final avatar = _header('Профиль');
        final previous = find.bySemanticsLabel('Предыдущий месяц');
        final next = find.bySemanticsLabel('Следующий месяц');
        _expectTapTarget(tester, search, 'search');
        _expectTapTarget(tester, avatar, 'avatar');
        _expectTapTarget(tester, previous, 'previous month');
        _expectTapTarget(tester, next, 'next month');

        await _tapAt(
          tester,
          tester.getRect(previous).topLeft + const Offset(1, 1),
        );
        expect(
          find.bySemanticsLabel('Сентябрь 2026, выбрать месяц'),
          findsOneWidget,
        );
        await _tapAt(
          tester,
          tester.getRect(next).bottomRight - const Offset(1, 1),
        );
        expect(
          find.bySemanticsLabel('Октябрь 2026, выбрать месяц'),
          findsOneWidget,
        );

        await _tapAt(
          tester,
          tester.getRect(search).bottomLeft + const Offset(1, -1),
        );
        expect(find.byType(SearchStubScreen), findsOneWidget);
        await h.systemBack();
        await _tapAt(
          tester,
          tester.getRect(avatar).topRight + const Offset(-1, 1),
        );
        expect(h.activeTab, AppNavTab.profile);
        await h.systemBack();
        expect(h.activeTab, AppNavTab.month);

        await tester.tap(find.bySemanticsLabel('Октябрь 2026, выбрать месяц'));
        await tester.pumpAndSettle();
        expect(_truncatedTexts(tester, width), isEmpty);
        final previousYear = find.bySemanticsLabel('Предыдущий год');
        final nextYear = find.bySemanticsLabel('Следующий год');
        _expectTapTarget(tester, previousYear, 'previous year');
        _expectTapTarget(tester, nextYear, 'next year');
        await _tapAt(
          tester,
          tester.getRect(previousYear).topLeft + const Offset(1, 1),
        );
        expect(_inPicker(find.text('2025')), findsOneWidget);
        await _tapAt(
          tester,
          tester.getRect(nextYear).bottomRight - const Offset(1, 1),
        );
        expect(_inPicker(find.text('2026')), findsOneWidget);
        await h.systemBack();

        await tester.tap(find.bySemanticsLabel(RegExp('^17 октября')));
        await tester.pumpAndSettle();
        expect(find.text('Суббота, 17 октября'), findsOneWidget);
        expect(_truncatedTexts(tester, width), isEmpty);
      });
    }
  }
}
