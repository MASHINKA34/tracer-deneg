import 'package:shared/shared.dart';

/// Тестовые месяцы для каталога компонентов и эталонных скриншотов —
/// суммы по дням ровно как на макетах Figma, чтобы сверять один к одному.
final class DemoMonth {
  const DemoMonth({
    required this.name,
    required this.figmaNode,
    required this.month,
    required this.today,
    required this.mood,
    required this.rubles,
    this.marks = const {},
  });

  /// Короткое имя для файлов эталонов: `autumn`, `newyear`, …
  final String name;

  /// Узел Figma, с которым сверяем.
  final String figmaNode;
  final YearMonth month;
  final LocalDate today;
  final Mood mood;

  /// Сумма дня в рублях (нет ключа — 0 ₽).
  final Map<int, int> rubles;

  /// Отметки праздников (число → эмодзи).
  final Map<int, String> marks;

  Map<int, Money> get dayTotals => {
    for (final e in rubles.entries) e.key: Money.rubles(e.value),
  };
}

/// Октябрь 2026, сегодня 19-е (главная `7:7`, карточка осени `16:2839`).
final DemoMonth demoAutumn = DemoMonth(
  name: 'autumn',
  figmaNode: '16:2839',
  month: YearMonth(2026, 10),
  today: LocalDate(2026, 10, 19),
  mood: Mood.autumn,
  rubles: const {
    1: 450, 2: 1280, 3: 2340, 5: 860, 6: 320, 7: 450, 8: 1150, 9: 540, //
    10: 2670, 11: 990, 12: 2900, 13: 210, 15: 760, 16: 430, 17: 1450, //
    18: 400, 19: 1100,
  },
);

/// Январь 2026 — прошедший месяц (карточка зимы `16:1816`).
final DemoMonth demoWinter = DemoMonth(
  name: 'winter',
  figmaNode: '16:1816',
  month: YearMonth(2026, 1),
  today: LocalDate(2026, 10, 19),
  mood: Mood.winter,
  rubles: const {
    2: 950, 3: 510, 4: 1110, 5: 240, 7: 2050, 8: 2510, 9: 140, 11: 120, //
    12: 1870, 13: 130, 14: 120, 15: 120, 16: 2420, 17: 1800, 18: 1270, //
    20: 170, 21: 120, 22: 150, 23: 120, 24: 630, 26: 410, 27: 230, //
    28: 2850, 30: 1180, 31: 640,
  },
);

/// Апрель 2026 — прошедший месяц (карточка весны `16:2102`).
final DemoMonth demoSpring = DemoMonth(
  name: 'spring',
  figmaNode: '16:2102',
  month: YearMonth(2026, 4),
  today: LocalDate(2026, 10, 19),
  mood: Mood.spring,
  rubles: const {
    2: 230, 3: 470, 4: 780, 5: 310, 7: 1440, 8: 1540, 9: 830, 11: 430, //
    12: 1920, 14: 680, 15: 140, 16: 2180, 17: 2540, 18: 1010, 19: 3120, //
    21: 470, 22: 2130, 23: 2020, 24: 260, 26: 960, 27: 2600, 28: 2220, //
    30: 1140,
  },
);

/// Июль 2026 — прошедший месяц (карточка лета `16:2520`).
final DemoMonth demoSummer = DemoMonth(
  name: 'summer',
  figmaNode: '16:2520',
  month: YearMonth(2026, 7),
  today: LocalDate(2026, 10, 19),
  mood: Mood.summer,
  rubles: const {
    1: 2100, 2: 850, 3: 1380, 4: 460, 5: 710, 6: 800, 7: 800, 8: 2870, //
    10: 1080, 11: 530, 12: 660, 13: 290, 14: 1810, 15: 120, 17: 1640, //
    18: 3260, 19: 550, 20: 780, 21: 2610, 24: 2520, 25: 710, 26: 2140, //
    27: 140, 28: 490, 29: 1680, 30: 1300, 31: 1110,
  },
);

/// Декабрь 2026, сегодня 29-е, праздничная карточка Нового года (`34:11425`).
final DemoMonth demoNewYear = DemoMonth(
  name: 'newyear',
  figmaNode: '34:11425',
  month: YearMonth(2026, 12),
  today: LocalDate(2026, 12, 29),
  mood: Mood.newyear,
  rubles: const {
    1: 1860, 2: 2630, 4: 120, 5: 140, 6: 2570, 8: 880, 9: 120, 10: 1100, //
    11: 1410, 12: 340, 13: 1570, 14: 2600, 16: 160, 17: 190, 18: 2300, //
    19: 1110, 20: 1630, 21: 440, 22: 620, 23: 870, 24: 2170, 25: 2710, //
    26: 2960, 27: 2830, 28: 2840, 29: 3150,
  },
  marks: const {31: '🎄'},
);

/// Октябрь 2026, сегодня 28-е, Хеллоуин (`34:10005` светлая, `34:10592`
/// тёмная).
final DemoMonth demoHalloween = DemoMonth(
  name: 'halloween',
  figmaNode: '34:10005',
  month: YearMonth(2026, 10),
  today: LocalDate(2026, 10, 28),
  mood: Mood.halloween,
  rubles: const {
    1: 450, 2: 1280, 3: 2340, 5: 860, 6: 320, 7: 450, 8: 1150, 9: 540, //
    10: 2670, 11: 990, 12: 2900, 13: 210, 15: 760, 16: 430, 17: 1450, //
    18: 400, 19: 1100, 20: 640, 21: 380, 23: 1730, 24: 2210, 25: 560, //
    26: 920, 27: 310, 28: 860,
  },
  marks: const {31: '🎃'},
);

/// Все тестовые месяцы — для эталонов карточки месяца.
final List<DemoMonth> demoMonths = [
  demoAutumn,
  demoWinter,
  demoSpring,
  demoSummer,
  demoNewYear,
  demoHalloween,
];

/// Тестовый месяц для настроения [mood] в каталоге: свой, если есть,
/// иначе октябрь с этим настроением.
DemoMonth demoMonthFor(Mood mood) {
  for (final m in demoMonths) {
    if (m.mood == mood) return m;
  }
  return DemoMonth(
    name: mood.name,
    figmaNode: '7:7',
    month: demoAutumn.month,
    today: demoAutumn.today,
    mood: mood,
    rubles: demoAutumn.rubles,
  );
}
