import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milionchik/features/month/month_picker_sheet.dart';
import 'package:milionchik/ui/components/month_card.dart';
import 'package:milionchik/ui/icons/app_icon.dart';

import '../../support/app_scope.dart';
import '../../support/test_fonts.dart';
import '../shell/shell_harness.dart';
import 'month_fixture.dart';

const String _previousLabel = 'Предыдущий месяц';

String _titleLabel(String month) => '$month 2026, выбрать месяц';

final Finder _chevronDown = find.descendant(
  of: find.byType(MonthCard),
  matching: find.byWidgetPredicate(
    (w) => w is AppIcon && w.icon == AppIcons.chevronDown,
  ),
);

Future<void> _tapAt(WidgetTester tester, Offset position) async {
  await tester.tapAt(position);
  await tester.pumpAndSettle();
}

void main() {
  const cases = [
    (width: 360.0, scale: 2.0, month: 'Октябрь', previous: 'Сентябрь'),
    (width: 320.0, scale: 2.0, month: 'Октябрь', previous: 'Сентябрь'),
    (width: 320.0, scale: 1.3, month: 'Сентябрь', previous: 'Август'),
  ];

  for (final c in cases) {
    testWidgets('${c.width.toInt()} dp, шрифт ${c.scale}, ${c.month}: '
        'нажатие на ▾ у правого края открывает выбор месяца, а не листает '
        'месяц; «‹» нажимается в своей области вне названия', (tester) async {
      await loadTestFonts();
      tester.platformDispatcher.textScaleFactorTestValue = c.scale;
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      final db = openTestDatabase();
      await tester.runAsync(() => seedMockupOctober(db));
      final h = await ShellHarness.start(
        tester,
        db: db,
        size: Size(c.width, 800),
      );
      if (c.month != 'Октябрь') {
        await tester.tap(find.bySemanticsLabel(_previousLabel));
        await tester.pumpAndSettle();
      }
      final title = find.bySemanticsLabel(_titleLabel(c.month));
      expect(title, findsOneWidget);

      final chevron = tester.getRect(_chevronDown);
      await _tapAt(tester, chevron.centerRight - const Offset(3, 0));
      expect(find.byType(MonthPicker), findsOneWidget);
      await h.systemBack();
      expect(find.byType(MonthPicker), findsNothing);
      expect(title, findsOneWidget);

      final titleRect = tester.getRect(title);
      final previousRect = tester.getRect(
        find.bySemanticsLabel(_previousLabel),
      );
      final freeLeft = math.max(previousRect.left, titleRect.right);
      expect(
        previousRect.right - freeLeft,
        greaterThanOrEqualTo(40),
        reason: 'title $titleRect, previous $previousRect',
      );
      await _tapAt(tester, Offset(freeLeft + 1, previousRect.top + 1));
      expect(find.byType(MonthPicker), findsNothing);
      expect(find.bySemanticsLabel(_titleLabel(c.previous)), findsOneWidget);
    });
  }
}
