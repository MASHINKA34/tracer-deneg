import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milionchik/ui/catalog/catalog_entries.dart';

import '../../support/golden.dart';

/// Эталоны компонентов: каждый раздел каталога в светлой и тёмной теме
/// (осень, шрифт 1.0) и в светлой при шрифте 2.0. Обновить:
/// `flutter test --update-goldens test/ui/golden`.
void main() {
  for (final entry in catalogEntries) {
    for (final (brightness, scale) in [
      (Brightness.light, 1.0),
      (Brightness.dark, 1.0),
      (Brightness.light, 2.0),
    ]) {
      final suffix =
          '${brightness.name}${scale == 1 ? '' : '_x${scale.toInt()}'}';
      testWidgets('${entry.id} $suffix (Figma ${entry.figmaNode})', (
        tester,
      ) async {
        await pumpGolden(
          tester,
          brightness: brightness,
          textScale: scale,
          background: entry.backgroundColor,
          child: Builder(builder: entry.builder),
        );
        if (entry.id == 'text_field') {
          // Второе поле — в фокусе (состояние Focused).
          await tester.tap(
            find.descendant(
              of: find.byKey(const ValueKey('field-focused')),
              matching: find.byType(EditableText),
            ),
          );
          await tester.pump();
        }
        await expectGolden(tester, 'components', '${entry.id}_$suffix');
      });
    }
  }
}
