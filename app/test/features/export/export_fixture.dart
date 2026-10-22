import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/app.dart';
import 'package:milionchik/core/clock.dart';
import 'package:milionchik/core/router.dart';
import 'package:milionchik/data/current_user.dart';
import 'package:milionchik/data/db/app_database.dart';
import 'package:milionchik/data/providers.dart';
import 'package:milionchik/data/repositories/categories_repository.dart';
import 'package:milionchik/data/repositories/expenses_repository.dart';
import 'package:milionchik/data/repositories/outbox_queue.dart';
import 'package:milionchik/data/repositories/prefs_repository.dart';
import 'package:milionchik/features/export/export_file.dart';
import 'package:milionchik/features/export/export_screen.dart';
import 'package:milionchik/features/month/month_screen.dart';
import 'package:milionchik/ui/components/button.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared/shared.dart';

import '../../support/app_scope.dart';

final class FakeSharer implements ExportSharer {
  final List<String> paths = [];
  final List<Uint8List> contents = [];
  ShareResult result = const ShareResult(
    'com.android.documentsui/.picker.SaveActivity',
    ShareResultStatus.success,
  );
  Object? error;

  @override
  Future<ShareResult> share(File file) async {
    paths.add(file.path);
    contents.add(file.readAsBytesSync());
    final failure = error;
    if (failure != null) throw failure;
    return result;
  }
}

typedef ExportSpend = (
  String category,
  int kopecks,
  LocalDate day,
  String comment,
  DateTime createdAt,
);

final List<ExportSpend> smallExportSpends = [
  (
    'Продукты',
    14990,
    LocalDate(2026, 10, 5),
    'Хлеб; молоко "Простоквашино"',
    DateTime(2026, 10, 5, 19, 10),
  ),
  ('Кафе', 64000, LocalDate(2026, 10, 5), '', DateTime(2026, 10, 5, 13, 30)),
  (
    'Транспорт',
    6400,
    LocalDate(2026, 10, 2),
    'Метро',
    DateTime(2026, 10, 2, 8),
  ),
  (
    'Развлечения',
    1250000,
    LocalDate(2026, 10, 19),
    '=Ёлка',
    DateTime(2026, 10, 19, 9, 15),
  ),
  (
    'Кафе',
    30000,
    LocalDate(2026, 9, 30),
    'Сентябрь',
    DateTime(2026, 9, 30, 12),
  ),
  (
    'Дом',
    640000,
    LocalDate(2025, 12, 28),
    'Коммуналка',
    DateTime(2025, 12, 28),
  ),
];

Future<String> seedSmallExport(AppDatabase db) async {
  final user = LocalPrefsCurrentUser(DriftPrefsRepository(db));
  final outbox = DriftOutboxQueue(db);
  final budget = await testBudgets(db).createLocalPersonal();
  final categories = await DriftCategoriesRepository(
    db,
    currentUser: user,
    outbox: outbox,
  ).watchByBudget(budget.id).first;
  final ids = {for (final c in categories) c.name: c.id};
  final expenses = DriftExpensesRepository(
    db,
    currentUser: user,
    outbox: outbox,
  );
  for (final (category, kopecks, day, comment, createdAt)
      in smallExportSpends) {
    final expense = await expenses.create(
      budgetId: budget.id,
      categoryId: ids[category]!,
      amount: Money(kopecks),
      spentOn: day,
      comment: comment,
    );
    await (db.update(db.expenses)..where((e) => e.id.equals(expense.id))).write(
      ExpensesCompanion(createdAt: Value(createdAt.toUtc())),
    );
  }
  return budget.id;
}

final class ExportHarness {
  ExportHarness._(this.tester, this.db, this.dir, this.sharer);

  final WidgetTester tester;
  final AppDatabase db;
  final Directory dir;
  final FakeSharer sharer;
  final List<LogRecord> records = [];

  static Future<ExportHarness> open(
    WidgetTester tester, {
    Future<void> Function(AppDatabase db)? seed,
    Size size = const Size(360, 800),
    ExportDirectory? directory,
    bool push = true,
  }) async {
    final db = openTestDatabase();
    await tester.runAsync(() => (seed ?? seedSmallExport)(db));
    final dir = Directory.systemTemp.createTempSync('milionchik_export_');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    final h = ExportHarness._(tester, db, dir, FakeSharer());

    final previousLevel = Logger.root.level;
    Logger.root.level = Level.ALL;
    final sub = Logger.root.onRecord.listen(h.records.add);
    addTearDown(() async {
      await sub.cancel();
      Logger.root.level = previousLevel;
    });

    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = size;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          clockProvider.overrideWithValue(Clock(now: () => testNow)),
          exportFilesProvider.overrideWithValue(
            ExportFiles(directory ?? () async => h.folder),
          ),
          exportSharerProvider.overrideWithValue(h.sharer),
        ],
        child: MilionchikApp(today: LocalDate.fromDateTime(testNow)),
      ),
    );
    await h.settle();
    if (push) {
      GoRouter.of(tester.element(find.byType(MonthScreen)))
          .push<void>(AppRoutes.export);
      await h.settle();
      expect(find.byType(ExportScreen), findsOneWidget);
    }
    return h;
  }

  Directory get folder =>
      Directory('${dir.path}${Platform.pathSeparator}export');

  List<String> get folderFiles => folder.existsSync()
      ? [
          for (final f in folder.listSync())
            f.uri.pathSegments.lastWhere((s) => s.isNotEmpty),
        ]
      : const [];

  Future<void> settle({bool Function()? until}) async {
    for (var i = 0; i < 100; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
      if (until == null ? i >= 4 : until()) break;
    }
    await tester.pumpAndSettle();
  }

  Finder get shareButton => find.descendant(
    of: find.byType(ExportScreen),
    matching: find.byType(AppButton),
  );

  bool get shareEnabled =>
      tester.widget<AppButton>(shareButton).onPressed != null;

  Future<void> share() async {
    final before = sharer.paths.length;
    await tester.tap(shareButton);
    await settle(until: () => sharer.paths.length > before);
  }

  Future<void> tapText(String text) async {
    await tester.tap(
      find.descendant(of: find.byType(ExportScreen), matching: find.text(text)),
    );
    await settle();
  }

  String get fileCardText => [
    for (final t in tester.widgetList<Text>(
      find.descendant(
        of: find.byType(ExportFileCard),
        matching: find.byType(Text),
      ),
    ))
      (t.data ?? '').replaceAll('​', '').replaceAll(nbsp, ' '),
  ].join(' | ');

  Iterable<LogRecord> exportLogs([Level? level]) => records.where(
    (r) => r.loggerName == 'export' && (level == null || r.level == level),
  );
}
