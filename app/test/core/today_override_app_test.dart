import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/app.dart';
import 'package:milionchik/core/clock.dart';
import 'package:milionchik/core/data_startup.dart';
import 'package:milionchik/data/api/token_store.dart';
import 'package:milionchik/data/db/app_database.dart';
import 'package:milionchik/data/repositories/prefs_repository.dart';
import 'package:milionchik/data/session/session.dart';
import 'package:milionchik/features/month/month_header.dart';
import 'package:milionchik/features/month/month_screen.dart';
import 'package:milionchik/ui/catalog/catalog_screen.dart';
import 'package:milionchik/ui/components/month_card.dart';
import 'package:milionchik/ui/theme/mood_colors.dart';
import 'package:shared/shared.dart';

void main() {
  late List<LogRecord> records;
  late StreamSubscription<LogRecord> sub;

  setUpAll(() => initializeDateFormatting('ru'));

  setUp(() {
    records = [];
    Logger.root.level = Level.ALL;
    sub = Logger.root.onRecord.listen(records.add);
  });

  tearDown(() => sub.cancel());

  List<String> lines(String logger, [Level level = Level.ALL]) => [
    for (final r in records)
      if (r.loggerName == logger && r.level >= level) formatLogRecord(r),
  ];

  LocalDate realToday() => LocalDate.fromDateTime(DateTime.now());

  Future<AppDatabase> startApp(WidgetTester tester, String? stored) async {
    tester.view
      ..devicePixelRatio = 2
      ..physicalSize = const Size(360, 800) * 2;
    addTearDown(tester.view.reset);
    final db = AppDatabase.memory();
    final data = await tester.runAsync(() async {
      if (stored != null) {
        await DriftPrefsRepository(db)
            .setString(PrefKeys.todayOverride, stored);
      }
      return startData(
        open: () async => db,
        readSession: () async => const Session(
          user: SessionUser(
            userId: 'user-today-1',
            login: 'today_user',
            displayName: 'Сегодня',
          ),
          tokens: AuthTokens(
            accessToken: 'ACCESS-today',
            refreshToken: 'REFRESH-today',
          ),
        ),
      );
    });
    await tester.pumpWidget(appRoot(data!));
    await tester.pumpAndSettle();
    return db;
  }

  Future<void> stopApp(WidgetTester tester, AppDatabase db) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
    await tester.runAsync(db.close);
  }

  Future<String?> storedOverride(WidgetTester tester, AppDatabase db) =>
      tester.runAsync<String?>(
        () => DriftPrefsRepository(db).getString(PrefKeys.todayOverride),
      );

  Future<void> openCatalog(WidgetTester tester) async {
    await tester.longPress(
      find
          .ancestor(
            of: find.byType(MonthHeader),
            matching: find.byType(GestureDetector),
          )
          .first,
    );
    await tester.pumpAndSettle();
  }

  Clock clockOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(MilionchikApp)))
          .read(clockProvider);

  Color accentOnMonth(WidgetTester tester) =>
      MoodColors.of(tester.element(find.byType(MonthScreen))).accent;

  Color accentOf(Mood mood) =>
      MoodColors.forMood(mood, Brightness.light).accent;

  Finder headerLabel() => find.descendant(
    of: find.byType(MonthHeaderView),
    matching: find.textContaining('debug '),
  );

  testWidgets('перезапуск с подменой из local_prefs: главная на 31 октября, '
      'акцент Хеллоуина, метка в шапке, warn «today overridden»', (
    tester,
  ) async {
    final db = await startApp(tester, '2026-10-31');

    expect(clockOf(tester).today(), LocalDate(2026, 10, 31));
    expect(
      tester.widget<MonthCard>(find.byType(MonthCard)).today,
      LocalDate(2026, 10, 31),
    );
    expect(accentOnMonth(tester), accentOf(Mood.halloween));
    expect(headerLabel(), findsOneWidget);
    expect(tester.widget<Text>(headerLabel()).data, startsWith('debug 31.10'));
    expect(lines('clock', Level.WARNING), [
      matches(
        RegExp(
          r'WARN  \[clock\] today overridden date=2026-10-31 '
          'real=${realToday()} key=debugTodayOverride in \\d+ms',
        ),
      ),
    ]);
    expect(
      lines('app', Level.INFO),
      contains(
        endsWith(
          'INFO  [app] mood=halloween today=2026-10-31 '
          '(holiday settings: defaults)',
        ),
      ),
    );

    await stopApp(tester, db);
  });

  testWidgets('без подмены: настоящая дата, метки в шапке нет, '
      'warn [clock] нет', (tester) async {
    final db = await startApp(tester, null);

    expect(clockOf(tester).today(), realToday());
    expect(tester.widget<MonthCard>(find.byType(MonthCard)).today, realToday());
    expect(headerLabel(), findsNothing);
    expect(lines('clock', Level.WARNING), isEmpty);

    await stopApp(tester, db);
  });

  testWidgets('каталог: «Сегодня = 19 октября» → выбор 31 → главная сразу '
      'на 31-м с Хеллоуином и меткой; «Сбросить» → настоящая дата', (
    tester,
  ) async {
    final db = await startApp(tester, '2026-10-19');
    expect(accentOnMonth(tester), accentOf(Mood.autumn));

    await openCatalog(tester);
    expect(find.byType(CatalogScreen), findsOneWidget);

    await tester.tap(find.textContaining('Сегодня = 19 октября'));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(DatePickerDialog),
        matching: find.text('31'),
      ),
    );
    await tester.pumpAndSettle();
    final ok = MaterialLocalizations.of(
      tester.element(find.byType(DatePickerDialog)),
    ).okButtonLabel;
    await tester.tap(find.text(ok));
    await tester.pumpAndSettle();

    expect(find.textContaining('Сегодня = 31 октября'), findsOneWidget);
    expect(await storedOverride(tester, db), '2026-10-31');
    expect(lines('clock', Level.INFO), [
      contains('WARN  [clock] today overridden date=2026-10-19'),
      matches(
        RegExp(
          r'INFO  \[clock\] today override set date=2026-10-31 '
          'real=${realToday()} previous=2026-10-19 in \\d+ms '
          r'\(debug build\)$',
        ),
      ),
    ]);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(CatalogScreen), findsNothing);
    expect(clockOf(tester).today(), LocalDate(2026, 10, 31));
    expect(
      tester.widget<MonthCard>(find.byType(MonthCard)).today,
      LocalDate(2026, 10, 31),
    );
    expect(accentOnMonth(tester), accentOf(Mood.halloween));
    expect(tester.widget<Text>(headerLabel()).data, startsWith('debug 31.10'));

    await openCatalog(tester);
    await tester.tap(find.text('Сбросить'));
    await tester.pumpAndSettle();

    expect(await storedOverride(tester, db), isNull);
    expect(
      lines('clock', Level.INFO).last,
      matches(
        RegExp(
          r'INFO  \[clock\] today override reset date=2026-10-31 → real date '
          '${realToday()} in \\d+ms \\(debug build\\)\$',
        ),
      ),
    );

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(clockOf(tester).today(), realToday());
    expect(tester.widget<MonthCard>(find.byType(MonthCard)).today, realToday());
    expect(headerLabel(), findsNothing);
    expect(
      accentOnMonth(tester),
      accentOf(moodOn(realToday(), const HolidaySettings())),
    );

    await stopApp(tester, db);
  });

  testWidgets('выбор даты отменён — подмены нет, в local_prefs пусто', (
    tester,
  ) async {
    final db = await startApp(tester, null);

    await openCatalog(tester);
    final reset = tester.widget<ButtonStyleButton>(
      find.ancestor(
        of: find.text('Сбросить'),
        matching: find.bySubtype<ButtonStyleButton>(),
      ),
    );
    expect(reset.onPressed, isNull);

    await tester.tap(find.textContaining('Сегодня = '));
    await tester.pumpAndSettle();
    final cancel = MaterialLocalizations.of(
      tester.element(find.byType(DatePickerDialog)),
    ).cancelButtonLabel;
    await tester.tap(find.text(cancel));
    await tester.pumpAndSettle();

    expect(find.byType(DatePickerDialog), findsNothing);
    expect(clockOf(tester).today(), realToday());
    expect(await storedOverride(tester, db), isNull);
    expect(lines('clock', Level.INFO), isEmpty);
    expect(
      records.map((r) => r.message),
      contains(startsWith('catalog today picker cancelled, today stays')),
    );

    await stopApp(tester, db);
  });
}
