import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared/shared.dart';

import '../../support/app_scope.dart';
import '../shell/shell_harness.dart';
import 'month_fixture.dart';

String _digits(String text) => text.replaceAll(' ', nbsp);

String _rub(String digits) => '${_digits(digits)}$nbsp₽';

const Map<int, String> _octoberSpent = {
  1: '450',
  2: '1 280',
  3: '2 340',
  5: '860',
  6: '320',
  7: '450',
  8: '1 150',
  9: '540',
  10: '2 670',
  11: '990',
  12: '2 900',
  13: '210',
  15: '760',
  16: '430',
  17: '1 450',
  18: '400',
  19: '1 100',
};

List<String> get _octoberDays => [
  for (var day = 1; day <= 31; day++)
    if (day > 19)
      '$day октября, будет'
    else if (_octoberSpent[day] case final spent?)
      '$day октября, потрачено ${_digits(spent)} рублей'
          '${day == 19 ? ', сегодня' : ''}'
    else
      '$day октября, трат нет',
];

List<String> _traversal(WidgetTester tester) => [
  for (final node in tester.semantics.simulatedAccessibilityTraversal())
    if (node.label.isNotEmpty) node.label,
];

List<String> _from(List<String> labels, String first) =>
    labels.skipWhile((label) => label != first).toList();

Future<ShellHarness> _october(WidgetTester tester) async {
  final db = openTestDatabase();
  await tester.runAsync(() => seedMockupOctober(db));
  return ShellHarness.start(tester, db: db);
}

void main() {
  testWidgets('ячейка 19 октября — одна кнопка «19 октября, потрачено 1 100 '
      'рублей, сегодня», 20 октября — «20 октября, будет», двойной тап '
      'TalkBack по 17 октября открывает шторку дня', (tester) async {
    await _october(tester);

    final today = tester.getSemantics(
      find.bySemanticsLabel(
        '19 октября, потрачено 1${nbsp}100 рублей, сегодня',
      ),
    );
    expect(
      today,
      isSemantics(
        label: '19 октября, потрачено 1${nbsp}100 рублей, сегодня',
        isButton: true,
        hasTapAction: true,
        hasSelectedState: true,
        isSelected: false,
      ),
    );
    expect(
      today.parent!.getSemanticsData().hasAction(SemanticsAction.tap),
      isFalse,
      reason: 'над ячейкой не должно быть второго узла без подписи с тапом',
    );

    final future = tester.getSemantics(
      find.bySemanticsLabel('20 октября, будет'),
    );
    expect(
      future,
      isSemantics(
        label: '20 октября, будет',
        isButton: false,
        hasTapAction: false,
      ),
    );
    expect(find.bySemanticsLabel('20 октября'), findsNothing);

    tester.semantics.tap(find.semantics.byLabel(RegExp('^17 октября')));
    await tester.pumpAndSettle();
    expect(find.text('Суббота, 17 октября'), findsOneWidget);
  });

  testWidgets('главная: порядок обхода — шапка слева направо, карточка '
      '(название, ‹ ›, дни 1–31, среднее, итог), «Сегодня» и траты, меню '
      'с «+» между «Статистикой» и «Регулярными»', (tester) async {
    await _october(tester);

    expect(_traversal(tester), [
      'Личный бюджет, выбрать бюджет',
      'Поиск',
      'Синхронизировано',
      'Профиль',
      'Октябрь 2026, выбрать месяц',
      'Предыдущий месяц',
      'Следующий месяц',
      ..._octoberDays,
      'В среднем\n${_rub('963')} / день',
      'Итог за месяц\n${_rub('18 300')}',
      'Сегодня, 19 октября',
      _rub('1 100'),
      'Продукты, Пятёрочка, 18:40, 640 рублей',
      'Транспорт, Метро, 2 поездки, 12:40, 250 рублей',
      'Кафе, Кофе с собой, 09:15, 210 рублей',
      'Месяц',
      'Статистика',
      'Добавить трату',
      'Регулярные',
      'Профиль',
    ]);
    expect(
      tester.getSemantics(
        find.bySemanticsLabel('Продукты, Пятёрочка, 18:40, 640 рублей'),
      ),
      isSemantics(isButton: true, hasTapAction: true),
    );
  });

  testWidgets('шторка выбора месяца: заголовок — header, год между ‹ и ›, '
      'эмодзи сезона не читается', (tester) async {
    await _october(tester);
    await tester.tap(find.bySemanticsLabel('Октябрь 2026, выбрать месяц'));
    await tester.pumpAndSettle();

    expect(
      tester.getSemantics(find.bySemanticsLabel('Выбор месяца')),
      isSemantics(isHeader: true),
    );
    expect(_from(_traversal(tester), 'Выбор месяца'), [
      'Выбор месяца',
      'Предыдущий год',
      '2026',
      'Следующий год',
      for (final name in [
        'Январь',
        'Февраль',
        'Март',
        'Апрель',
        'Май',
        'Июнь',
        'Июль',
        'Август',
        'Сентябрь',
        'Октябрь',
        'Ноябрь',
        'Декабрь',
      ])
        '$name 2026',
      'Октябрь 2026 · идёт сейчас',
      _rub('18 300'),
      'на ${_rub('2 100')} меньше, чем в сентябре',
      'В среднем ${_rub('963')} в день',
      startsWith('Высота столбика'),
      'Открыть октябрь',
    ]);
    expect(find.bySemanticsLabel('🍂'), findsNothing);
  });

  testWidgets('шторка дня: заголовок, итог, сводка, траты кнопками с '
      'категорией, комментарием, временем и суммой словами', (tester) async {
    await _october(tester);
    await tester.tap(find.bySemanticsLabel(RegExp('^17 октября')));
    await tester.pumpAndSettle();

    expect(_from(_traversal(tester), 'Суббота, 17 октября'), [
      'Суббота, 17 октября',
      _rub('1 450'),
      '2 траты · больше среднего на ${_rub('487')}',
      'Кафе, Обед с коллегами, 13:30, 890 рублей',
      'Продукты, ВкусВилл, 19:10, 560 рублей',
      'Нажми на трату, чтобы изменить. Смахни влево — удалить.',
      'Добавить трату в этот день',
    ]);
    expect(
      tester.getSemantics(
        find.bySemanticsLabel('Кафе, Обед с коллегами, 13:30, 890 рублей'),
      ),
      isSemantics(isButton: true, hasTapAction: true),
    );
  });

  testWidgets('у каждого нажимаемого элемента главной, выбора месяца и '
      'шторки дня есть подпись', (tester) async {
    final harness = await _october(tester);
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

    await tester.tap(find.bySemanticsLabel('Октябрь 2026, выбрать месяц'));
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await harness.systemBack();

    await tester.tap(find.bySemanticsLabel(RegExp('^17 октября')));
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  });
}
