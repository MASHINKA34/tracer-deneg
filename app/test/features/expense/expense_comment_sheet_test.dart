import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/core/clock.dart';
import 'package:milionchik/data/providers.dart';
import 'package:milionchik/data/queries/search_queries.dart';
import 'package:milionchik/features/expense/expense_comment_sheet.dart';
import 'package:milionchik/features/expense/new_expense_screen.dart';
import 'package:milionchik/l10n/app_localizations.dart';
import 'package:milionchik/ui/components/chip.dart';
import 'package:milionchik/ui/components/sheet.dart';
import 'package:milionchik/ui/components/snackbar.dart';
import 'package:milionchik/ui/components/tap_target.dart';
import 'package:milionchik/ui/components/text_field.dart';
import 'package:milionchik/ui/theme/app_theme.dart';
import 'package:shared/shared.dart';

import '../../support/app_scope.dart';
import '../../support/test_fonts.dart';
import '../month/month_fixture.dart';
import '../shell/shell_harness.dart';
import 'expense_comment_fixture.dart';
import 'new_expense_harness.dart';

const String _secret = 'Подарок маме на юбилей';

Finder _inSheet(Finder finder) =>
    find.descendant(of: find.byType(ExpenseCommentSheet), matching: finder);

Finder _chip(String label) => find.widgetWithText(AppChip, label);

List<String> _recentChips(WidgetTester tester) => [
  for (final e in _inSheet(find.byType(AppChip)).evaluate())
    (e.widget as AppChip).label,
];

String _field(WidgetTester tester) => tester
    .widget<EditableText>(_inSheet(find.byType(EditableText)))
    .controller
    .text;

Future<(ShellHarness, String)> _start(
  WidgetTester tester, {
  List<String> comments = const [],
  Size size = const Size(360, 800),
  double scale = 1,
}) async {
  await loadTestFonts();
  if (scale != 1) {
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.platformDispatcher.clearAllTestValues);
  }
  final db = openTestDatabase();
  final budgetId = (await tester.runAsync(() async {
    final id = await seedMockupOctober(db);
    await seedComments(db, comments, budgetId: id);
    return id;
  }))!;
  final h = await ShellHarness.start(tester, db: db, size: size);
  await h.tapPlus();
  return (h, budgetId);
}

Future<void> _openSheet(WidgetTester tester, [String chip = 'Комментарий']) =>
    _tap(tester, inNewExpense(_chip(chip)));

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _done(WidgetTester tester) =>
    _tap(tester, _inSheet(find.text('Готово')));

Iterable<LogRecord> _expenseDebug(ShellHarness h) =>
    h.records.where((r) => r.loggerName == 'expense' && r.level == Level.FINE);

void _expectNoText(ShellHarness h, String text) {
  for (final r in h.records) {
    final line = '${r.message} ${r.error ?? ''}';
    expect(line, isNot(contains(text)), reason: line);
  }
}

final class _FailingSearchQueries implements SearchQueries {
  @override
  Stream<SearchResult> watchSearch(SearchFilters filters) =>
      const Stream.empty();

  @override
  Stream<List<String>> watchRecentComments(
    String budgetId, {
    int limit = recentCommentsLimit,
  }) => Stream.error(
    SqliteException(
      extendedResultCode: 10,
      message: 'disk I/O error',
      causingStatement: 'SELECT "comment" FROM "expenses" WHERE "comment" = ?',
      parametersToStatement: [_secret],
    ),
  );
}

void main() {
  test('чип комментария: до 24 символов как есть, длиннее — 23 символа и '
      '«…», эмодзи — один символ', () {
    expect(commentChipLabel('Кофе с собой'), 'Кофе с собой');
    final exact = 'а' * commentChipMaxChars;
    expect(commentChipLabel(exact), exact);
    expect(
      commentChipLabel('Обед с коллегами в кафе у работы'),
      'Обед с коллегами в кафе…',
    );
    expect(commentChipLabel('${'👨‍👩‍👧' * 30}x'), '${'👨‍👩‍👧' * 23}…');
  });

  testWidgets('101-й символ не вводится: поле с автофокусом, 101 символ → '
      '100 и счётчик 100 / 100, ещё символ — текст тот же, эмодзи-семья — '
      'один символ; в debug-логе только длины', (tester) async {
    final (h, _) = await _start(tester);
    await _openSheet(tester);

    expect(_inSheet(find.text('Комментарий')), findsOneWidget);
    expect(_inSheet(find.text('Что купил')), findsOneWidget);
    expect(_inSheet(find.text('0 / 100')), findsOneWidget);
    final editable = tester.widget<EditableText>(
      _inSheet(find.byType(EditableText)),
    );
    expect(editable.focusNode.hasFocus, isTrue);
    expect(editable.textInputAction, TextInputAction.done);

    final hundredOne = '${'а' * 99}бв';
    await tester.enterText(_inSheet(find.byType(EditableText)), hundredOne);
    await tester.pumpAndSettle();
    expect(_field(tester), '${'а' * 99}б');
    expect(_inSheet(find.text('100 / 100')), findsOneWidget);

    tester.testTextInput.updateEditingValue(
      TextEditingValue(
        text: '${_field(tester)}г',
        selection: const TextSelection.collapsed(offset: 101),
      ),
    );
    await tester.pumpAndSettle();
    expect(_field(tester), '${'а' * 99}б');
    expect(_inSheet(find.text('100 / 100')), findsOneWidget);

    await tester.enterText(_inSheet(find.byType(EditableText)), '');
    await tester.pumpAndSettle();
    expect(_inSheet(find.text('0 / 100')), findsOneWidget);
    await tester.enterText(
      _inSheet(find.byType(EditableText)),
      '${'👨‍👩‍👧' * 100}ы',
    );
    await tester.pumpAndSettle();
    expect(_field(tester), '👨‍👩‍👧' * 100);
    expect(_inSheet(find.text('100 / 100')), findsOneWidget);

    expect(
      _expenseDebug(h).map((r) => r.message),
      containsAll([
        'comment input over max=100: entered 101 chars, kept 100',
        'comment input over max=100: entered 101 chars, kept 100',
      ]),
    );
    _expectNoText(h, 'ааааа');
  });

  testWidgets('«Недавние» — 6 последних уникальных свежими первыми: повторы '
      'один раз, седьмой и старше не видны', (tester) async {
    await _start(
      tester,
      comments: const [
        'Метро',
        'Пятёрочка',
        'Метро',
        'Обед',
        'Кофе с собой',
        'Пятёрочка',
        'Аптека',
        'Цветы',
        'Такси',
      ],
    );
    await _openSheet(tester);

    expect(_inSheet(find.text('Недавние')), findsOneWidget);
    expect(_recentChips(tester), [
      'Метро',
      'Пятёрочка',
      'Обед',
      'Кофе с собой',
      'Аптека',
      'Цветы',
    ]);
  });

  testWidgets('тап по недавнему подставляет его в поле вместо набранного, '
      'счётчик 12 / 100; «Готово» → чип «Кофе с собой», трата сохраняется с '
      'комментарием, в логах только длина', (tester) async {
    final (h, budgetId) = await _start(tester, comments: mockupRecentComments);
    await _openSheet(tester);
    await tester.enterText(_inSheet(find.byType(EditableText)), 'Кофе');
    await tester.pumpAndSettle();

    await _tap(tester, _inSheet(_chip('Кофе с собой')));
    expect(_field(tester), 'Кофе с собой');
    expect(_inSheet(find.text('12 / 100')), findsOneWidget);
    final editable = tester.widget<EditableText>(
      _inSheet(find.byType(EditableText)),
    );
    expect(editable.controller.selection.baseOffset, 'Кофе с собой'.length);

    await _done(tester);
    expect(find.byType(ExpenseCommentSheet), findsNothing);
    expect(inNewExpense(_chip('Кофе с собой')), findsOneWidget);

    final today = LocalDate(2026, 10, 19);
    final before = await allExpenses(tester, h.db, budgetId, today);
    await typeKeys(tester, '1250');
    await tapCategory(tester, 'Кафе');
    expect(find.byType(NewExpenseScreen), findsNothing);
    final after = await allExpenses(tester, h.db, budgetId, today);
    final saved = after.firstWhere((e) => !before.any((b) => b.id == e.id));
    expect(saved.comment, 'Кофе с собой');
    expect(saved.amount, const Money.rubles(1250));

    expect(
      _expenseDebug(h).map((r) => r.message),
      containsAll([
        'comment sheet opened length=0 budgetId=$budgetId',
        'comment sheet recent budgetId=$budgetId count=6',
        'comment recent #3 picked length=12',
        'expense comment set length=12 was=0',
        'expense saved id=${saved.id} amountKopecks=125000',
      ]),
    );
    expect(
      _expenseDebug(h).map((r) => r.message),
      contains(matches(r'^comment sheet done length=12 after \d+ms$')),
    );
    _expectNoText(h, 'Кофе с собой');
  });

  for (final kind in const [
    PointerDeviceKind.touch,
    PointerDeviceKind.stylus,
    PointerDeviceKind.mouse,
  ]) {
    testWidgets('тап по недавнему (${kind.name}) оставляет фокус в поле — '
        'клавиатура не прячется, курсор в конце', (tester) async {
      final (h, _) = await _start(tester, comments: mockupRecentComments);
      await _openSheet(tester);
      final chip = _inSheet(_chip('Обед'));
      await tester.ensureVisible(chip);
      await tester.pumpAndSettle();
      await tester.tap(chip, kind: kind);
      await tester.pumpAndSettle();

      final editable = tester.widget<EditableText>(
        _inSheet(find.byType(EditableText)),
      );
      expect(editable.controller.text, 'Обед');
      expect(editable.focusNode.hasFocus, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
      expect(editable.controller.selection.baseOffset, 4);
      _expectNoText(h, 'Обед');
    });
  }

  testWidgets('«Готово» на клавиатуре применяет комментарий; пробелы по '
      'краям убираются; повторное открытие — с текстом, длинный в чипе '
      'сокращён', (tester) async {
    final (h, _) = await _start(tester);
    await _openSheet(tester);
    await tester.enterText(
      _inSheet(find.byType(EditableText)),
      '  Обед с коллегами в кафе у работы  ',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.byType(ExpenseCommentSheet), findsNothing);
    expect(inNewExpense(_chip('Обед с коллегами в кафе…')), findsOneWidget);

    await _openSheet(tester, 'Обед с коллегами в кафе…');
    expect(_field(tester), 'Обед с коллегами в кафе у работы');
    expect(_inSheet(find.text('32 / 100')), findsOneWidget);
    _expectNoText(h, 'Обед с коллегами');
  });

  testWidgets('закрытие без «Готово» («назад») — комментарий прежний; '
      'очистка поля и «Готово» — снова «Комментарий» и трата без '
      'комментария', (tester) async {
    final (h, budgetId) = await _start(tester);
    await _openSheet(tester);
    await tester.enterText(_inSheet(find.byType(EditableText)), 'Метро');
    await _done(tester);
    expect(inNewExpense(_chip('Метро')), findsOneWidget);

    await _openSheet(tester, 'Метро');
    await tester.enterText(_inSheet(find.byType(EditableText)), 'Такси');
    await tester.pumpAndSettle();
    await h.systemBack();
    expect(find.byType(ExpenseCommentSheet), findsNothing);
    expect(find.byType(NewExpenseScreen), findsOneWidget);
    expect(inNewExpense(_chip('Метро')), findsOneWidget);
    expect(
      _expenseDebug(h).map((r) => r.message),
      contains(
        matches(
          r'^comment sheet closed without done after \d+ms: back gesture, '
          r'tap outside or swipe down, comment stays length=5$',
        ),
      ),
    );

    await _openSheet(tester, 'Метро');
    await tester.enterText(_inSheet(find.byType(EditableText)), '   ');
    await _done(tester);
    expect(inNewExpense(_chip('Комментарий')), findsOneWidget);

    final today = LocalDate(2026, 10, 19);
    final before = await allExpenses(tester, h.db, budgetId, today);
    await typeKeys(tester, '70');
    await tapCategory(tester, 'Транспорт');
    final after = await allExpenses(tester, h.db, budgetId, today);
    final saved = after.firstWhere((e) => !before.any((b) => b.id == e.id));
    expect(saved.comment, '');
  });

  testWidgets('ошибка записи траты с комментарием: снекбар, error [expense] и '
      '[repo] без текста комментария и значений параметров SQL', (
    tester,
  ) async {
    final (h, _) = await _start(tester);
    await tester.runAsync(
      () => h.db.customStatement(
        'CREATE TRIGGER expenses_fail BEFORE INSERT ON expenses '
        "BEGIN SELECT RAISE(ABORT, 'disk I/O error'); END",
      ),
    );
    await _openSheet(tester);
    await tester.enterText(_inSheet(find.byType(EditableText)), _secret);
    await _done(tester);
    await typeKeys(tester, '5000');
    await tapCategory(tester, 'Кафе');

    expect(find.byType(NewExpenseScreen), findsOneWidget);
    expect(find.byType(AppSnackbar), findsOneWidget);
    final errors = [
      for (final r in h.records)
        if (r.level == Level.SEVERE && r.loggerName == 'expense') r,
    ];
    expect(errors, hasLength(1));
    expect(errors.single.message, contains('INSERT INTO "expenses"'));
    expect(errors.single.message, contains('disk I/O error'));
    expect(errors.single.message, contains('<text:${_secret.length}>'));
    _expectNoText(h, _secret);
    _expectNoText(h, 'Подарок');
  });

  testWidgets('ошибка чтения недавних: шторка без «Недавних», поле и '
      '«Готово» работают, error [expense] без значений параметров SQL', (
    tester,
  ) async {
    await loadTestFonts();
    final records = <LogRecord>[];
    final previous = Logger.root.level;
    Logger.root.level = Level.ALL;
    final sub = Logger.root.onRecord.listen(records.add);
    addTearDown(() async {
      await sub.cancel();
      Logger.root.level = previous;
    });
    final db = openTestDatabase();
    final budgetId = (await tester.runAsync(
      () => seedComments(db, mockupRecentComments),
    ))!;
    String? result;
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(360, 800);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          clockProvider.overrideWithValue(Clock(now: () => testNow)),
          searchQueriesProvider.overrideWithValue(_FailingSearchQueries()),
        ],
        child: MaterialApp(
          theme: AppTheme.build(Brightness.light, Mood.autumn),
          locale: const Locale('ru'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () async => result = await showExpenseCommentSheet(
                    context,
                    initial: '',
                    budgetId: budgetId,
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byType(ExpenseCommentSheet), findsOneWidget);
    expect(_inSheet(find.text('Недавние')), findsNothing);
    final errors = [
      for (final r in records)
        if (r.level == Level.SEVERE && r.loggerName == 'expense') r,
    ];
    expect(errors, hasLength(1));
    expect(
      errors.single.message,
      startsWith(
        'comment sheet recent comments failed budgetId=$budgetId, sheet '
        'shown without them: SqliteException',
      ),
    );
    expect(errors.single.stackTrace, isNotNull);
    for (final r in records) {
      expect('${r.message} ${r.error ?? ''}', isNot(contains(_secret)));
    }

    await tester.enterText(_inSheet(find.byType(EditableText)), 'Метро');
    await _done(tester);
    expect(result, 'Метро');
  });

  for (final (width, scale) in const [
    (360.0, 1.0),
    (320.0, 1.0),
    (360.0, 2.0),
    (320.0, 2.0),
  ]) {
    testWidgets('$width dp, шрифт $scale, клавиатура 300: без переполнений, '
        'поле и «Готово» над клавиатурой после прокрутки, недавние '
        'нажимаются в 48 по высоте и не заходят на соседние', (tester) async {
      final (_, _) = await _start(
        tester,
        comments: mockupRecentComments,
        size: Size(width, 800),
        scale: scale,
      );
      await _openSheet(tester);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final keyboardTop = 800 - 300.0;
      final field = _inSheet(find.byType(AppTextField));
      await tester.ensureVisible(field);
      await tester.pumpAndSettle();
      expect(tester.getRect(field).bottom, lessThanOrEqualTo(keyboardTop));
      final done = _inSheet(find.text('Готово'));
      await tester.ensureVisible(done);
      await tester.pumpAndSettle();
      expect(tester.getRect(done).bottom, lessThanOrEqualTo(keyboardTop));

      final chips = [
        for (final e in _inSheet(find.byType(AppChip)).evaluate())
          (
            area: tester.getRect(
              find.descendant(
                of: find.byWidget(e.widget),
                matching: find.byType(TapTarget),
              ),
            ),
            visual: tester.getRect(
              find
                  .descendant(
                    of: find.byWidget(e.widget),
                    matching: find.byType(Material),
                  )
                  .first,
            ),
          ),
      ];
      expect(chips, hasLength(6));
      for (final a in chips) {
        expect(a.area.height, greaterThanOrEqualTo(kMinTapTarget));
        for (final b in chips) {
          if (identical(a, b)) continue;
          expect(a.area.overlaps(b.visual), isFalse, reason: '$a / $b');
        }
      }

      await _tap(tester, _inSheet(_chip('Метро')));
      expect(_field(tester), 'Метро');
      await _done(tester);
      expect(find.byType(AppSheet), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
