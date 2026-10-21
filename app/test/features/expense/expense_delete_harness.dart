import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/app.dart';
import 'package:milionchik/core/clock.dart';
import 'package:milionchik/data/current_user.dart';
import 'package:milionchik/data/db/app_database.dart';
import 'package:milionchik/data/providers.dart';
import 'package:milionchik/data/queries/month_queries.dart';
import 'package:milionchik/data/repositories/expenses_repository.dart';
import 'package:milionchik/data/repositories/outbox_queue.dart';
import 'package:milionchik/data/repositories/prefs_repository.dart';
import 'package:milionchik/features/month/day_sheet.dart';
import 'package:milionchik/features/month/today_block.dart';
import 'package:milionchik/ui/components/bottom_nav.dart';
import 'package:milionchik/ui/components/snackbar.dart';
import 'package:shared/shared.dart';

import '../../support/app_scope.dart';
import '../../support/test_fonts.dart';
import '../month/month_fixture.dart';

final LocalDate deleteDay = LocalDate(2026, 10, 19);

String rub(String digits) => '${digits.replaceAll(' ', nbsp)}$nbsp₽';

final class DeleteHarness {
  DeleteHarness._(this.tester, this.db);

  final WidgetTester tester;
  final AppDatabase db;
  final List<LogRecord> records = [];
  late final String budgetId;
  late final Map<String, Expense> byComment;
  late final DateTime _fakeStart;
  Duration skew = Duration.zero;

  DateTime get now =>
      testNow.add(tester.binding.clock.now().difference(_fakeStart) + skew);

  static Future<DeleteHarness> start(
    WidgetTester tester, {
    Size size = const Size(360, 800),
    double textScale = 1,
  }) async {
    await loadTestFonts();
    final h = DeleteHarness._(tester, openTestDatabase())
      .._fakeStart = tester.binding.clock.now();
    final previousLevel = Logger.root.level;
    Logger.root.level = Level.ALL;
    final sub = Logger.root.onRecord.listen(h.records.add);
    addTearDown(() async {
      await sub.cancel();
      Logger.root.level = previousLevel;
    });

    final seeded = (await tester.runAsync(() async {
      final budgetId = await seedMockupOctober(h.db);
      final day = await DriftMonthQueries(h.db)
          .watchDayExpenses(budgetId, deleteDay)
          .first;
      return (budgetId, {for (final e in day) e.comment: e});
    }))!;
    h
      ..budgetId = seeded.$1
      ..byComment = seeded.$2;

    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = size;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(h.db),
          clockProvider.overrideWithValue(Clock(now: () => h.now)),
        ],
        child: MilionchikApp(today: deleteDay),
      ),
    );
    await tester.pumpAndSettle();
    return h;
  }

  Expense get pyaterochka => byComment['Пятёрочка']!;

  Expense get metro => byComment['Метро, 2 поездки']!;

  Expense get coffee => byComment['Кофе с собой']!;

  ExpensesRepository get expenses => DriftExpensesRepository(
    db,
    currentUser: LocalPrefsCurrentUser(DriftPrefsRepository(db)),
    outbox: DriftOutboxQueue(db),
    now: () => now,
  );

  Future<Expense?> stored(String id) =>
      tester.runAsync<Expense?>(() => expenses.watchById(id).first);

  Future<List<OutboxEntry>> outbox() async =>
      (await tester.runAsync(() => db.select(db.outbox).get()))!;

  Future<List<PendingChange>> due() async => (await tester.runAsync(
    () => DriftOutboxQueue(db, now: () => now).pending(),
  ))!;

  Future<void> settle() async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pumpAndSettle();
  }

  Future<void> wait(Duration duration) => tester.pump(duration);

  Future<void> waitSinceDelete(Duration duration) async {
    final deletedAt = (await outbox()).last.createdAt;
    await tester.pump(deletedAt.add(duration).difference(now));
  }

  Finder get today => find.byType(TodayBlock);

  Finder inToday(Finder finder) => find.descendant(of: today, matching: finder);

  Finder inDay(Finder finder) =>
      find.descendant(of: find.byType(DaySheet), matching: finder);

  Finder todayRow(String subtitle) => inToday(find.text(subtitle));

  Finder dayRow(String subtitle) => inDay(find.text(subtitle));

  Future<void> swipe(Finder row) async {
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.drag(row, const Offset(-300, 0));
    await settle();
  }

  Future<void> openDay(String date) async {
    await tester.tap(find.bySemanticsLabel(RegExp('^$date')));
    await tester.pumpAndSettle();
  }

  Finder get snackbar => find.byType(AppSnackbar);

  Finder get undoButton =>
      find.descendant(of: snackbar, matching: find.text('Отменить'));

  Future<void> tapUndo() async {
    await tester.tap(undoButton);
    await settle();
  }

  double get navTop => tester.getTopLeft(find.byType(AppBottomNav)).dy;

  Iterable<String> messages(String logger, Level level) => [
    for (final r in records)
      if (r.loggerName == logger && r.level == level) r.message,
  ];
}
