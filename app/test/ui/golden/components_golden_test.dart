import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milionchik/ui/catalog/catalog_entries.dart';
import 'package:shared/shared.dart' show Mood;

import '../../support/golden.dart';

/// Эталоны компонентов: каждый раздел каталога в светлой и тёмной теме
/// (осень, шрифт 1.0), в светлой при шрифте 2.0 и в обеих темах в
/// настроении «1 сентября» — единственном, где `accent` (заливки) и
/// `accent-strong` (текст и обводки) различаются (00-spec §6.2), поэтому
/// только эти снимки ловят их путаницу. Обновить:
/// `flutter test --update-goldens test/ui/golden`.
void main() {
  for (final entry in catalogEntries) {
    for (final (brightness, scale, mood) in [
      (Brightness.light, 1.0, Mood.autumn),
      (Brightness.dark, 1.0, Mood.autumn),
      (Brightness.light, 2.0, Mood.autumn),
      (Brightness.light, 1.0, Mood.knowledge),
      (Brightness.dark, 1.0, Mood.knowledge),
    ]) {
      final suffix =
          '${mood == Mood.autumn ? '' : '${mood.name}_'}${brightness.name}'
          '${scale == 1 ? '' : '_x${scale.toInt()}'}';
      testWidgets('${entry.id} $suffix (Figma ${entry.figmaNode})', (
        tester,
      ) async {
        await pumpGolden(
          tester,
          brightness: brightness,
          mood: mood,
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
