import 'package:flutter_test/flutter_test.dart';
import 'package:milionchik/features/recurring/recurring_overview.dart';
import 'package:shared/shared.dart';

final DateTime _at = DateTime.utc(2026, 10, 1);

const String _budget = 'budget-1';

final LocalDate _today = LocalDate(2026, 10, 19);

final YearMonth _october = YearMonth(2026, 10);

Category _category(String id, {bool system = false}) => Category(
  id: id,
  budgetId: _budget,
  name: id,
  emoji: system ? '📦' : '🎵',
  color: system ? null : CategoryColor.pink,
  sortOrder: 0,
  isSystem: system,
  updatedAt: _at,
  updatedBy: 'user',
);

final List<Category> _categories = [
  _category('music'),
  _category('net'),
  _category('other', system: true),
];

RecurringRule _rule(
  String id,
  int rubles,
  int day, {
  String category = 'music',
  YearMonth? from,
  DateTime? deletedAt,
}) => RecurringRule(
  id: id,
  budgetId: _budget,
  categoryId: category,
  title: id,
  amount: Money.rubles(rubles),
  dayOfMonth: day,
  startMonth: from ?? _october,
  createdAt: _at,
  updatedAt: _at,
  updatedBy: 'user',
  deletedAt: deletedAt,
);

Expense _charge(RecurringRule rule, {int? rubles, LocalDate? on}) => Expense(
  id: recurringExpenseId(rule.id, _october),
  budgetId: _budget,
  categoryId: rule.categoryId,
  amount: rubles == null ? rule.amount : Money.rubles(rubles),
  spentOn: on ?? chargeDate(rule.dayOfMonth, _october),
  comment: rule.title,
  authorId: 'user',
  recurringId: rule.id,
  recurringMonth: _october,
  createdAt: _at,
  updatedAt: _at,
  updatedBy: 'user',
);

RecurringOverview _overview(
  List<RecurringRule> rules,
  List<Expense> charges, {
  LocalDate? today,
  List<Category>? categories,
}) => RecurringOverview.of(
  budgetId: _budget,
  today: today ?? _today,
  rules: rules,
  charges: {for (final e in charges) e.recurringId!: e},
  categories: categories ?? _categories,
);

void main() {
  final music = _rule('Музыка', 199, 24);
  final cinema = _rule('Онлайн-кино', 299, 28);
  final internet = _rule('Домашний интернет', 650, 3, category: 'net');
  final mobile = _rule('Мобильная связь', 450, 7, category: 'net');
  final gym = _rule('Спортзал', 2900, 12);
  final mockup = [internet, mobile, gym, music, cinema];

  test('данные макета 12:1047 на 19 октября: каждый месяц 4 498 ₽, 5 правил; '
      'скоро 24-е через 5 дней и 28-е через 9 дней на 498 ₽; уже списано 3, '
      '7 и 12 октября на 4 000 ₽', () {
    final o = _overview(mockup, [
      _charge(internet),
      _charge(mobile),
      _charge(gym),
    ]);

    expect(o.monthly, const Money.rubles(4498));
    expect(o.monthly.formatTotal(), '4${nbsp}498$nbsp₽');
    expect(o.ruleCount, 5);
    expect(o.isEmpty, isFalse);
    expect(o.month, _october);
    expect(
      [for (final u in o.upcoming) '${u.rule.title} ${u.date} ${u.days}'],
      ['Музыка 2026-10-24 5', 'Онлайн-кино 2026-10-28 9'],
    );
    expect(o.upcomingTotal, const Money.rubles(498));
    expect(
      [for (final c in o.charged) '${c.rule.title} ${c.expense.spentOn}'],
      [
        'Домашний интернет 2026-10-03',
        'Мобильная связь 2026-10-07',
        'Спортзал 2026-10-12',
      ],
    );
    expect(o.chargedTotal, const Money.rubles(4000));
    expect(o.unknownCategoryIds, isEmpty);
  });

  test('скоро — по ближайшей дате, а не по дню месяца: правило со стартом в '
      'ноябре на 1-е идёт после 28 октября', () {
    final november = _rule('С ноября', 100, 1, from: YearMonth(2026, 11));
    final o = _overview([november, cinema, music], const []);

    expect(
      [for (final u in o.upcoming) '${u.rule.title} ${u.date} ${u.days}'],
      [
        'Музыка 2026-10-24 5',
        'Онлайн-кино 2026-10-28 9',
        'С ноября 2026-11-01 13',
      ],
    );
    expect(o.charged, isEmpty);
    expect(o.monthly, const Money.rubles(598));
  });

  test('трату этого месяца удалили — правило в «Скоро» со следующим '
      'списанием 3 ноября, а не в «Уже списано»', () {
    final o = _overview([internet, mobile], [_charge(mobile)]);

    expect(o.charged.map((c) => c.rule.title), ['Мобильная связь']);
    expect(o.upcoming.single.rule.title, 'Домашний интернет');
    expect(o.upcoming.single.date, LocalDate(2026, 11, 3));
    expect(o.upcoming.single.days, 15);
  });

  test('день списания сегодня, трату ещё не создали — следующее списание '
      'через месяц; трата есть — в «Уже списано»', () {
    final today = LocalDate(2026, 10, 24);

    final before = _overview([music], const [], today: today);
    final after = _overview([music], [_charge(music)], today: today);

    expect(before.upcoming.single.date, LocalDate(2026, 11, 24));
    expect(before.upcoming.single.days, 31);
    expect(after.upcoming, isEmpty);
    expect(after.charged.single.expense.spentOn, today);
  });

  test('сумму правила поменяли после списания: в «Уже списано» сумма траты, '
      'в «Каждый месяц» — новая сумма правила', () {
    final raised = _rule('Домашний интернет', 700, 3, category: 'net');
    final o = _overview([raised], [_charge(raised, rubles: 650)]);

    expect(o.monthly, const Money.rubles(700));
    expect(o.chargedTotal, const Money.rubles(650));
    expect(o.charged.single.expense.amount, const Money.rubles(650));
  });

  test('категории правила нет среди живых — «Другое», id в unknown; '
      'удалённое правило не считается', () {
    final lost = _rule('Без категории', 300, 25, category: 'gone');
    final removed = _rule('Удалённое', 999, 20, deletedAt: _at);
    final o = _overview([lost, removed], const []);

    expect(o.ruleCount, 1);
    expect(o.monthly, const Money.rubles(300));
    expect(o.upcoming.single.category?.id, 'other');
    expect(o.unknownCategoryIds, {'gone'});
  });

  test('правил нет — пусто, суммы нулевые', () {
    final o = _overview(const [], const []);
    final none = RecurringOverview.empty(budgetId: null, today: _today);

    expect(o.isEmpty, isTrue);
    expect(o.monthly, Money.zero);
    expect(o.upcomingTotal, Money.zero);
    expect(o.chargedTotal, Money.zero);
    expect(none.isEmpty, isTrue);
    expect(none.budgetId, isNull);
  });
}
