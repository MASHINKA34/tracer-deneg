import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milionchik/features/search/search_field.dart';

import 'search_fixture.dart';

bool _focused(WidgetTester tester) =>
    tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus;

void main() {
  testWidgets('нажатие в любом месте строки поиска — у края, над текстом, по '
      'лупе — ставит фокус в поле и не снимает его', (tester) async {
    await openSearch(tester);
    final pill = tester.getRect(find.byType(SearchField));
    final top = pill.top + 2;
    final bottom = pill.bottom - 2;
    final points = {
      'над текстом у верхнего края': Offset(pill.left + 150, top + 3),
      'под текстом у нижнего края': Offset(pill.left + 150, bottom - 3),
      'по лупе': Offset(pill.left + 26, (top + bottom) / 2),
    };

    for (final MapEntry(key: where, value: point) in points.entries) {
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      expect(_focused(tester), isFalse, reason: where);

      await tester.tapAt(point);
      await tester.pump();
      expect(_focused(tester), isTrue, reason: where);

      await tester.tapAt(point);
      await tester.pump();
      expect(_focused(tester), isTrue, reason: '$where, второе нажатие');
    }
  });
}
