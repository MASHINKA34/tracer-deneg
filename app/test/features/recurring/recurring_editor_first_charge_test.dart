import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'recurring_editor_harness.dart';

const String _every =
    'Трата сама появится в календаре в этот день каждого месяца.';

String _shortMonths(String example) =>
    'Если в месяце нет такого дня (например, $example) — спишем в последний '
    'день месяца.';

Finder _text(RecurringEditorHarness h, String text) =>
    h.inEditor(find.text(text.replaceAll('NBSP', ' ')));

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testWidgets('новое правило 19 октября: по умолчанию 19-е — «Первая трата '
      'появится сегодня, 19 октября.»; 20-е (не прошло) — «20 октября»; 18-е '
      '(прошло) — «18 ноября»', (tester) async {
    final h = await RecurringEditorHarness.start(tester);
    await h.openNew();

    expect(h.rowLabel('День списания'), 'День списания, 19-е число');
    expect(
      _text(h, 'Первая трата появится сегодня, 19NBSPоктября.'),
      findsOneWidget,
    );
    expect(_text(h, _every), findsOneWidget);

    await h.pickDay(20);
    expect(h.rowLabel('День списания'), 'День списания, 20-е число');
    expect(_text(h, 'Первая трата появится 20NBSPоктября.'), findsOneWidget);

    await h.pickDay(18);
    expect(_text(h, 'Первая трата появится 18NBSPноября.'), findsOneWidget);
    expect(find.textContaining('Первая трата появится'), findsOneWidget);
    expect(find.textContaining('Если в месяце нет'), findsNothing);
  });

  testWidgets('5 ноября, 31-е: «Первая трата появится 30 ноября.» и '
      'подсказка про короткие месяцы «31-го в апреле»; 30-е и 29-е — «в '
      'феврале», 28-е — без неё', (tester) async {
    final h = await RecurringEditorHarness.start(
      tester,
      now: DateTime(2026, 11, 5, 12),
    );
    await h.openNew();

    await h.pickDay(31);
    expect(h.rowLabel('День списания'), 'День списания, 31-е число');
    expect(_text(h, 'Первая трата появится 30NBSPноября.'), findsOneWidget);
    expect(
      _text(h, '$_every ${_shortMonths('31-го в апреле')}'),
      findsOneWidget,
    );

    await h.pickDay(30);
    expect(_text(h, 'Первая трата появится 30NBSPноября.'), findsOneWidget);
    expect(
      _text(h, '$_every ${_shortMonths('30-го в феврале')}'),
      findsOneWidget,
    );

    await h.pickDay(29);
    expect(_text(h, 'Первая трата появится 29NBSPноября.'), findsOneWidget);
    expect(
      _text(h, '$_every ${_shortMonths('29-го в феврале')}'),
      findsOneWidget,
    );

    await h.pickDay(28);
    expect(_text(h, _every), findsOneWidget);
    expect(find.textContaining('Если в месяце нет'), findsNothing);

    await h.pickDay(4);
    expect(_text(h, 'Первая трата появится 4NBSPдекабря.'), findsOneWidget);
  });

  testWidgets('31 декабря, 10-е: первая трата в следующем году — «10 января '
      '2027»', (tester) async {
    final h = await RecurringEditorHarness.start(
      tester,
      now: DateTime(2026, 12, 31, 12),
    );
    await h.openNew();
    expect(
      _text(h, 'Первая трата появится сегодня, 31NBSPдекабря.'),
      findsOneWidget,
    );

    await h.pickDay(10);
    expect(
      _text(h, 'Первая трата появится 10NBSPянваряNBSP2027.'),
      findsOneWidget,
    );
  });

  testWidgets('правка существующего правила: подсказки «Первая трата» нет, '
      'для 12-го — только общая, для 31-го — с короткими месяцами', (
    tester,
  ) async {
    final h = await RecurringEditorHarness.start(tester);
    await h.openRule(gymTitle);

    expect(h.rowLabel('День списания'), 'День списания, 12-е число');
    expect(find.textContaining('Первая трата появится'), findsNothing);
    expect(_text(h, _every), findsOneWidget);

    await h.pickDay(31);
    expect(
      _text(h, '$_every ${_shortMonths('31-го в апреле')}'),
      findsOneWidget,
    );
    expect(find.textContaining('Первая трата появится'), findsNothing);
  });
}
