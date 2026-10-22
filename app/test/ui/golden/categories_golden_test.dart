import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milionchik/core/router.dart';
import 'package:milionchik/l10n/app_localizations.dart';
import 'package:milionchik/ui/components/button.dart';
import 'package:milionchik/ui/theme/app_theme.dart';
import 'package:shared/shared.dart';

import '../../features/categories/categories_fixture.dart';
import '../../support/app_scope.dart';
import '../../support/golden.dart';
import '../../support/test_fonts.dart';

Future<void> _pump(
  WidgetTester tester, {
  required Brightness brightness,
  required double width,
  required double scale,
  required double height,
  required Future<String> Function(CategoriesFixture f, Category cafe) location,
}) async {
  await loadTestFonts();
  final db = openTestDatabase();
  final initial = (await tester.runAsync(() async {
    final fixture = await CategoriesFixture.mockup(db);
    return location(fixture, await fixture.byName('Кафе'));
  }))!;
  debugDisableShadows = false;
  tester.view
    ..devicePixelRatio = goldenPixelRatio
    ..physicalSize = Size(width, height) * goldenPixelRatio
    ..viewPadding = const FakeViewPadding(top: 32)
    ..padding = const FakeViewPadding(top: 32);
  addTearDown(tester.view.reset);
  tester.platformDispatcher
    ..textScaleFactorTestValue = scale
    ..accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
      disableAnimations: true,
    );
  addTearDown(tester.platformDispatcher.clearAllTestValues);

  final router = buildRouter(initialLocation: initial);
  addTearDown(router.dispose);
  final base = AppTheme.build(brightness, Mood.autumn);

  await tester.pumpWidget(
    withDatabase(
      db,
      RepaintBoundary(
        key: goldenKey,
        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,
          theme: base.copyWith(
            textTheme: base.textTheme.apply(
              fontFamilyFallback: const [testEmojiFamily],
            ),
          ),
          locale: const Locale('ru'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          routerConfig: router,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await settleAssets(tester);
}

Future<void> _scrollToEnd(WidgetTester tester) async {
  final scrollable = tester.state<ScrollableState>(
    find.byType(Scrollable).first,
  );
  scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
  await tester.pumpAndSettle();
  await settleAssets(tester);
}

Future<void> _openDeleteDialog(WidgetTester tester) async {
  final delete = find.widgetWithText(AppButton, 'Удалить категорию');
  await tester.ensureVisible(delete);
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    await tester.tap(delete);
    await Future<void>.delayed(const Duration(milliseconds: 200));
  });
  await tester.pumpAndSettle();
  final scrollable = tester.state<ScrollableState>(
    find.byType(Scrollable).first,
  );
  scrollable.position.jumpTo(0);
  await tester.pumpAndSettle();
  await settleAssets(tester);
}

String _name(Brightness brightness, double width, double scale) =>
    '${brightness.name}_${width.toInt()}'
    '${scale == 1 ? '' : '_x${scale.toInt()}'}';

Future<String> _list(CategoriesFixture f, Category cafe) async =>
    AppRoutes.categories;

Future<String> _cafe(CategoriesFixture f, Category cafe) async =>
    AppRoutes.categoryOf(cafe.id);

Future<String> _new(CategoriesFixture f, Category cafe) async =>
    AppRoutes.newCategory;

Future<String> _other(CategoriesFixture f, Category cafe) async =>
    AppRoutes.categoryOf((await f.other()).id);

void main() {
  for (final brightness in Brightness.values) {
    for (final width in const [360.0, 320.0]) {
      for (final scale in const [1.0, 2.0]) {
        final name = _name(brightness, width, scale);
        testWidgets('«Категории» 10 категорий и «Другое» $name '
            '(Figma 44:4792)', (tester) async {
          await _pump(
            tester,
            brightness: brightness,
            width: width,
            scale: scale,
            height: 840,
            location: _list,
          );

          await expectGolden(tester, 'categories', 'list_$name');
        });

        testWidgets('«Категория» Кафе $name (Figma 44:4902)', (tester) async {
          await _pump(
            tester,
            brightness: brightness,
            width: width,
            scale: scale,
            height: 800,
            location: _cafe,
          );

          await expectGolden(tester, 'categories', 'editor_$name');
        });

        testWidgets('«Удалить «Кафе»?» 11 трат $name (Figma 44:5010)', (
          tester,
        ) async {
          await _pump(
            tester,
            brightness: brightness,
            width: width,
            scale: scale,
            height: 800,
            location: _cafe,
          );
          await _openDeleteDialog(tester);

          await expectGolden(tester, 'categories', 'delete_$name');
        });

        if (scale != 1) {
          testWidgets('«Категории» $name прокручены до подписи', (
            tester,
          ) async {
            await _pump(
              tester,
              brightness: brightness,
              width: width,
              scale: scale,
              height: 840,
              location: _list,
            );
            await _scrollToEnd(tester);

            await expectGolden(tester, 'categories', 'list_${name}_end');
          });

          testWidgets('«Категория» Кафе $name прокручена до подсказки', (
            tester,
          ) async {
            await _pump(
              tester,
              brightness: brightness,
              width: width,
              scale: scale,
              height: 800,
              location: _cafe,
            );
            await _scrollToEnd(tester);

            await expectGolden(tester, 'categories', 'editor_${name}_end');
          });
        }
      }
    }

    testWidgets('«Новая категория» пустая ${brightness.name}_360', (
      tester,
    ) async {
      await _pump(
        tester,
        brightness: brightness,
        width: 360,
        scale: 1,
        height: 800,
        location: _new,
      );

      await expectGolden(tester, 'categories', 'new_${brightness.name}');
    });

    testWidgets('«Новая категория»: «Сохранить» без названия — ошибка под '
        'полем, выбран 🐾 и синий ${brightness.name}_360', (tester) async {
      await _pump(
        tester,
        brightness: brightness,
        width: 360,
        scale: 1,
        height: 800,
        location: _new,
      );
      await tester.tap(find.bySemanticsLabel('🐾'));
      await tester.tap(find.bySemanticsLabel('Синий'));
      await tester.pump();
      await tester.tap(find.widgetWithText(AppButton, 'Сохранить'));
      await tester.pumpAndSettle();
      await settleAssets(tester);

      await expectGolden(tester, 'categories', 'new_error_${brightness.name}');
    });

    testWidgets('«Другое» по адресу — экран «не меняется» '
        '${brightness.name}_360', (tester) async {
      await _pump(
        tester,
        brightness: brightness,
        width: 360,
        scale: 1,
        height: 800,
        location: _other,
      );

      await expectGolden(tester, 'categories', 'system_${brightness.name}');
    });
  }
}
