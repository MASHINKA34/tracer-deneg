import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milionchik/l10n/app_localizations.dart';
import 'package:milionchik/ui/theme/app_theme.dart';
import 'package:shared/shared.dart' show Mood;

import 'test_fonts.dart';

/// Ключ области, которую снимает эталон.
const Key goldenKey = ValueKey('golden');

/// Плотность пикселей эталонов: 1× (`matchesGoldenFile` снимает слой в
/// логических пикселях) — как скриншоты Figma для сверки.
const double goldenPixelRatio = 1;

/// Рисует [child] для эталонного скриншота: тема дизайн-системы
/// ([brightness], [mood]), русская локаль, ширина [width] dp, масштаб
/// шрифта [textScale], подложка [background] (по умолчанию `bg/app`).
///
/// Отличие от приложения только одно: в тестах нет системного эмодзи-шрифта,
/// поэтому к теме добавлен запасной шрифт Segoe UI Emoji (см. test_fonts).
Future<void> pumpGolden(
  WidgetTester tester, {
  required Widget child,
  required Brightness brightness,
  Mood mood = Mood.autumn,
  double width = 360,
  double textScale = 1,
  Color? Function(BuildContext context)? background,
  EdgeInsets padding = const EdgeInsets.all(16),
}) async {
  await loadTestFonts();
  EditableText.debugDeterministicCursor = true;
  addTearDown(() => EditableText.debugDeterministicCursor = false);
  // flutter_test по умолчанию рисует тени без размытия (debugDisableShadows),
  // а нам для сверки с Figma нужны настоящие тени card / raised / sheet.
  // Вернуть флаг нужно до конца теста — это делает [expectGolden].
  debugDisableShadows = false;
  tester.view
    ..devicePixelRatio = goldenPixelRatio
    ..physicalSize = Size(width, 3000) * goldenPixelRatio;
  addTearDown(tester.view.reset);

  final base = AppTheme.build(brightness, mood);
  final theme = base.copyWith(
    textTheme: base.textTheme.apply(
      fontFamilyFallback: const [testEmojiFamily],
    ),
  );
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      locale: const Locale('ru'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: Material(
            color: context.colors.bgApp,
            child: DefaultTextStyle.merge(
              style: const TextStyle(fontFamilyFallback: [testEmojiFamily]),
              child: Align(
                alignment: Alignment.topLeft,
                child: RepaintBoundary(
                  key: goldenKey,
                  child: Builder(
                    builder: (context) => Container(
                      width: width,
                      color: background?.call(context) ?? context.colors.bgApp,
                      padding: padding,
                      child: child,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await settleAssets(tester);
}

/// SVG-иконки грузятся асинхронно (разбор в отдельном изоляте): даём им
/// загрузиться реальным временем и перерисовываем.
Future<void> settleAssets(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
  }
}

/// Имя файла эталона.
String goldenName(String group, String name) => 'goldens/$group/$name.png';

/// Сравнивает снимок с эталоном `goldens/<group>/<name>.png`, затем убирает
/// дерево (таймеры курсора и анимаций) и возвращает флаг теней — его
/// flutter_test проверяет до tearDown.
Future<void> expectGolden(
  WidgetTester tester,
  String group,
  String name,
) async {
  try {
    await expectLater(
      find.byKey(goldenKey),
      matchesGoldenFile(goldenName(group, name)),
    );
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    debugDisableShadows = true;
  }
}
