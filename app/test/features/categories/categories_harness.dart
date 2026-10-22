import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/core/router.dart';
import 'package:milionchik/features/categories/categories_screen.dart';
import 'package:milionchik/features/categories/category_editor_screen.dart';
import 'package:milionchik/ui/components/button.dart';
import 'package:milionchik/ui/components/text_field.dart';
import 'package:shared/shared.dart';

import '../../support/app_scope.dart';
import '../shell/shell_harness.dart';
import 'categories_fixture.dart';

final class CategoriesHarness {
  CategoriesHarness(this.shell, this.fixture);

  final ShellHarness shell;
  final CategoriesFixture fixture;

  WidgetTester get tester => shell.tester;

  static Future<CategoriesHarness> start(
    WidgetTester tester, {
    bool mockup = true,
    Size size = const Size(360, 800),
  }) async {
    final db = openTestDatabase();
    final fixture = (await tester.runAsync(
      () =>
          mockup ? CategoriesFixture.mockup(db) : CategoriesFixture.presets(db),
    ))!;
    final shell = await ShellHarness.start(tester, db: db, size: size);
    return CategoriesHarness(shell, fixture);
  }

  Future<T> read<T>(Future<T> Function() body) async =>
      (await tester.runAsync(body)) as T;

  Future<T> write<T>(Future<T> Function() body) async {
    late T result;
    Object? error;
    var done = false;
    unawaited(
      body().then(
        (value) {
          result = value;
          done = true;
        },
        onError: (Object e) {
          error = e;
          done = true;
        },
      ),
    );
    for (var i = 0; i < 250 && !done; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(done, isTrue, reason: 'database work did not finish');
    if (error != null) throw error!;
    await tester.pumpAndSettle();
    return result;
  }

  Future<List<Category>> stored() => read(fixture.list);

  Future<Category> named(String name) => read(() => fixture.byName(name));

  GoRouter get router =>
      GoRouter.of(tester.element(find.byType(Navigator).first));

  String get location => router.state.uri.toString();

  Future<void> go(String location) async {
    unawaited(router.push<void>(location));
    await tester.pumpAndSettle();
  }

  Future<void> openList() => go(AppRoutes.categories);

  Finder inList(Finder finder) =>
      find.descendant(of: find.byType(CategoriesScreen), matching: finder);

  Finder inEditor(Finder finder) =>
      find.descendant(of: find.byType(CategoryEditorScreen), matching: finder);

  Finder row(String name) =>
      inList(find.bySemanticsLabel(RegExp('^${RegExp.escape(name)}, ')));

  List<String> shownNames(Iterable<String> names) {
    final shown = [
      for (final name in names)
        if (inList(find.text(name)).evaluate().isNotEmpty)
          (name, tester.getTopLeft(inList(find.text(name))).dy),
    ]..sort((a, b) => a.$2.compareTo(b.$2));
    return [for (final (name, _) in shown) name];
  }

  String rowLabel(String name) => tester.getSemantics(row(name)).label;

  Future<void> tapRow(String name) async {
    await tester.ensureVisible(row(name));
    await tester.pumpAndSettle();
    await tester.tap(row(name));
    await tester.pumpAndSettle();
  }

  Future<void> tapAdd() async {
    await tester.tap(inList(find.bySemanticsLabel('Новая категория')));
    await tester.pumpAndSettle();
  }

  Finder get nameField => inEditor(
    find.descendant(
      of: find.byType(AppTextField),
      matching: find.byType(EditableText),
    ),
  );

  Future<void> typeName(String text) async {
    await tester.enterText(nameField, text);
    await tester.pump();
  }

  Finder get saveButton =>
      inEditor(find.widgetWithText(AppButton, 'Сохранить'));

  Finder get deleteButton =>
      inEditor(find.widgetWithText(AppButton, 'Удалить категорию'));

  Future<void> tapButton(Finder button) async {
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  Future<void> pumpUntil(Finder finder) async {
    for (var i = 0; i < 250 && finder.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pumpAndSettle();
  }

  Future<void> tapSemantics(String label) async {
    final target = inEditor(find.bySemanticsLabel(label));
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Iterable<LogRecord> logs([Level level = Level.ALL]) => shell.records.where(
    (r) => r.loggerName == 'categories' && r.level >= level,
  );

  Iterable<String> messages([Level level = Level.ALL]) =>
      logs(level).map((r) => r.message);
}
