import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/features/recurring/recurring_day_sheet.dart';
import 'package:milionchik/features/recurring/recurring_editor_screen.dart';
import 'package:milionchik/features/recurring/recurring_screen.dart';

import 'recurring_editor_harness.dart';
import 'recurring_fixture.dart';

void _expectNotLogged(
  RecurringEditorHarness h, {
  required String title,
  required String kopecks,
}) {
  for (final r in h.shell.records) {
    final text = '${r.message} ${r.error ?? ''}';
    expect(text, isNot(contains(title)), reason: text);
    if (r.level >= Level.INFO) {
      expect(text, isNot(contains(kopecks)), reason: text);
    }
  }
}

Future<void> _fillNew(RecurringEditorHarness h) async {
  await h.openNew();
  await h.typeTitle('Квартплата Барсика');
  await h.enterAmount('4500');
  await h.pickCategory('Связь');
}

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testWidgets('правило не записалось в базу: снекбар, редактор и ввод '
      'остаются, error [recurring] с типом и мс без названия и параметров '
      'SQL', (tester) async {
    final h = await RecurringEditorHarness.start(tester);
    await h.read(
      () => h.shell.db.customStatement(
        'CREATE TRIGGER recurring_fail BEFORE INSERT ON recurring_rules '
        "BEGIN SELECT RAISE(ABORT, 'disk I/O error'); END",
      ),
    );
    await _fillNew(h);

    await h.save();

    expect(find.byType(RecurringEditorScreen), findsOneWidget);
    expect(
      find.text('Не удалось сохранить регулярную трату. Попробуй ещё раз'),
      findsOneWidget,
    );
    expect(h.inEditor(find.text('Квартплата Барсика')), findsOneWidget);
    final errors = h.logs(Level.SEVERE).toList();
    expect(errors, hasLength(1));
    expect(
      errors.single.message,
      matches(
        r'^recurring save failed new fields=title,amount,category,day after '
        r'\d+ms, nothing saved: SqliteException',
      ),
    );
    expect(errors.single.message, contains('disk I/O error'));
    expect(errors.single.stackTrace, isNotNull);
    expect(await h.rules(), hasLength(5));
    _expectNotLogged(h, title: 'Барсика', kopecks: '450000');
  });

  testWidgets('генератор после сохранения упал: правило сохранено, экран '
      'закрыт, warn [recurring] «трата создастся при следующем запуске»', (
    tester,
  ) async {
    final h = await RecurringEditorHarness.start(tester);
    await h.read(
      () => h.shell.db.customStatement(
        'CREATE TRIGGER expenses_fail BEFORE INSERT ON expenses '
        "BEGIN SELECT RAISE(ABORT, 'disk I/O error'); END",
      ),
    );
    await _fillNew(h);

    await h.save();

    expect(find.byType(RecurringEditorScreen), findsNothing);
    expect(find.byType(RecurringScreen), findsOneWidget);
    final rule = (await h.rules()).singleWhere(
      (r) => r.title == 'Квартплата Барсика',
    );
    expect(await h.expensesOf(rule.id), isEmpty);
    final warnings = h.messages(Level.WARNING).toList();
    expect(
      warnings,
      contains(
        matches(
          r'^recurring save new: rule is saved but the generator after save '
          r'failed \(failedRules=\d+ error=.+\), due expenses will be created '
          r'on the next run$',
        ),
      ),
    );
    _expectNotLogged(h, title: 'Барсика', kopecks: '450000');
  });

  testWidgets('debug [recurring]: открытие, поля, шторка дня, выход без '
      'сохранения с несохранёнными полями; названия и суммы нет', (
    tester,
  ) async {
    final h = await RecurringEditorHarness.start(tester);
    await _fillNew(h);
    await h.openDaySheet();
    await tester.tap(h.dayCell(25));
    await tester.pump();
    await h.shell.systemBack();
    expect(find.byType(RecurringDaySheet), findsNothing);
    await h.pickDay(25);
    await h.shell.systemBack();

    expect(find.byType(RecurringEditorScreen), findsNothing);
    expect(
      h.messages(Level.FINE),
      containsAllInOrder([
        'recurring editor opened new',
        'recurring edit new title changed length=18 error=none',
        'recurring edit new amount tap → amount sheet',
        'recurring edit new amount set kopecks=450000',
        'recurring edit new category tap → sheet with 14 categories',
        matches(r'^recurring edit new category none → [0-9a-f-]{36}$'),
        'recurring edit new day tap day=19 → day sheet',
        'day sheet opened day=19',
        'day sheet selected 19 → 25',
        matches(
          r'^day sheet closed without done after \d+ms: back gesture, tap '
          r'outside or swipe down, day stays 19$',
        ),
        'recurring edit new day tap day=19 → day sheet',
        matches(r'^day sheet done day=25 after \d+ms$'),
        'recurring edit new day today → 25',
        'recurring editor new closed by back with unsaved '
            'fields=title,amount,category,day → changes discarded',
      ]),
    );
    expect(h.shell.navDebug(), contains('recurring editor closed new by back'));
    expect(h.logs(Level.WARNING), isEmpty);
    expect(await h.rules(), hasLength(5));
    for (final r in h.logs()) {
      expect(r.message, isNot(contains('Квартплата')), reason: r.message);
      expect(r.message, isNot(contains('₽')), reason: r.message);
    }
  });

  testWidgets('правило удалили, пока редактор открыт: экран «Регулярная '
      'трата не найдена», info [recurring]', (tester) async {
    final h = await RecurringEditorHarness.start(tester);
    final gym = h.budget.rules[gymTitle]!;
    await h.openRule(gymTitle);

    await writeWhileShown(tester, () => h.budget.recurring.delete(gym.id));
    await h.pumpUntil(find.text('Регулярная трата не найдена'));

    expect(find.text('Регулярная трата не найдена'), findsOneWidget);
    expect(
      find.text('Возможно, её удалили — здесь или на другом телефоне.'),
      findsOneWidget,
    );
    expect(
      h.messages(Level.INFO),
      contains(
        'recurring editor id=${gym.id}: rule was deleted while the screen '
        'was open → not found screen',
      ),
    );
    await tester.tap(find.text('Назад').last);
    await tester.pumpAndSettle();
    expect(find.byType(RecurringScreen), findsOneWidget);
  });

  testWidgets('открыли несуществующее правило: «Регулярная трата не найдена» '
      'и warn [recurring] с id', (tester) async {
    final h = await RecurringEditorHarness.start(tester);
    await h.shell.tapTab('Регулярные');
    h.router.go('/recurring/missing-rule');
    await tester.pumpAndSettle();

    expect(find.text('Регулярная трата не найдена'), findsOneWidget);
    expect(
      h.messages(Level.WARNING),
      contains(
        'recurring editor id=missing-rule: rule is not found → not found '
        'screen',
      ),
    );
  });
}
