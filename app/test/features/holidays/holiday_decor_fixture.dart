import 'package:milionchik/data/current_user.dart';
import 'package:milionchik/data/db/app_database.dart';
import 'package:milionchik/data/repositories/categories_repository.dart';
import 'package:milionchik/data/repositories/expenses_repository.dart';
import 'package:milionchik/data/repositories/outbox_queue.dart';
import 'package:milionchik/data/repositories/prefs_repository.dart';
import 'package:milionchik/ui/catalog/demo_months.dart';
import 'package:shared/shared.dart';

import '../../support/app_scope.dart';
import 'holiday_banner_fixture.dart';

typedef HolidayCardFigma = ({
  Map<int, int> rubles,
  String lightCard,
  String darkCard,
  String lightDecor,
  String darkDecor,
});

final Map<HolidayKey, HolidayCardFigma> figmaHolidayCards = {
  HolidayKey.newyear: (
    rubles: const {
      1: 300,
      2: 3310,
      3: 2290,
      5: 310,
      7: 1420,
      11: 620,
      12: 180,
      14: 2140,
      15: 1610,
      16: 670,
      17: 550,
      19: 1850,
      20: 1520,
      21: 720,
      22: 570,
      23: 1850,
      24: 490,
      25: 120,
      26: 450,
      28: 1370,
      29: 160,
    },
    lightCard: '31:4040',
    darkCard: '31:4355',
    lightDecor: '31:4041',
    darkDecor: '31:4356',
  ),
  HolidayKey.valentine: (
    rubles: const {
      1: 3200,
      2: 170,
      4: 660,
      5: 2770,
      6: 760,
      7: 2770,
      9: 1800,
      10: 2530,
      11: 230,
    },
    lightCard: '31:4687',
    darkCard: '31:4953',
    lightDecor: '31:4688',
    darkDecor: '31:4954',
  ),
  HolidayKey.defender: (
    rubles: const {
      1: 2100,
      2: 850,
      3: 1380,
      4: 460,
      5: 710,
      6: 800,
      7: 800,
      8: 2870,
      10: 1080,
      11: 530,
      12: 660,
      13: 290,
      14: 1810,
      15: 120,
      17: 1640,
      18: 3260,
      19: 550,
      20: 780,
      21: 2610,
    },
    lightCard: '31:5237',
    darkCard: '31:5491',
    lightDecor: '31:5238',
    darkDecor: '31:5492',
  ),
  HolidayKey.maslenitsa: (
    rubles: const {
      1: 440,
      2: 1060,
      3: 1300,
      4: 1370,
      5: 710,
      6: 1000,
      7: 530,
      8: 1400,
      9: 280,
      10: 540,
      11: 1130,
      12: 420,
      13: 2740,
      14: 460,
      15: 490,
      16: 290,
      17: 230,
      19: 2530,
    },
    lightCard: '31:5762',
    darkCard: '31:6276',
    lightDecor: '31:5763',
    darkDecor: '31:6277',
  ),
  HolidayKey.women: (
    rubles: const {1: 740, 2: 830, 3: 160, 5: 120},
    lightCard: '32:6145',
    darkCard: '32:6453',
    lightDecor: '32:6146',
    darkDecor: '32:6454',
  ),
  HolidayKey.labour: (
    rubles: const {1: 160, 2: 190, 3: 150, 4: 2270},
    lightCard: '32:6778',
    darkCard: '32:7116',
    lightDecor: '32:6779',
    darkDecor: '32:7117',
  ),
  HolidayKey.victory: (
    rubles: const {2: 720, 3: 2400, 4: 3180, 5: 380, 7: 230, 8: 300},
    lightCard: '32:7471',
    darkCard: '32:7866',
    lightDecor: '32:7472',
    darkDecor: '32:7867',
  ),
  HolidayKey.children: (
    rubles: const {1: 2000},
    lightCard: '32:8278',
    darkCard: '32:8601',
    lightDecor: '32:8279',
    darkDecor: '32:8602',
  ),
  HolidayKey.knowledge: (
    rubles: const {1: 2340},
    lightCard: '33:8281',
    darkCard: '33:8590',
    lightDecor: '33:8282',
    darkDecor: '33:8591',
  ),
  HolidayKey.halloween: (
    rubles: demoHalloween.rubles,
    lightCard: '33:8916',
    darkCard: '33:9344',
    lightDecor: '33:8917',
    darkDecor: '33:9345',
  ),
  HolidayKey.birthday: (
    rubles: const {
      1: 1480,
      2: 1660,
      5: 400,
      6: 150,
      7: 160,
      8: 500,
      9: 120,
      10: 1610,
      11: 990,
    },
    lightCard: '33:9789',
    darkCard: '33:10152',
    lightDecor: '33:9790',
    darkDecor: '33:10153',
  ),
};

Mood holidayMood(HolidayKey key) => Mood.values.byName(key.name);

Future<void> seedFigmaHolidayCard(
  AppDatabase db,
  HolidayExample example,
) async {
  final prefs = DriftPrefsRepository(db);
  if (example.key == HolidayKey.birthday) {
    await prefs.setString(PrefKeys.localUserId, anya.userId);
  }
  final user = LocalPrefsCurrentUser(prefs);
  final outbox = DriftOutboxQueue(db);
  final budget = await testBudgets(db).createLocalPersonal();
  final category = (await DriftCategoriesRepository(
    db,
    currentUser: user,
    outbox: outbox,
  ).watchByBudget(budget.id).first).first;
  final expenses = DriftExpensesRepository(
    db,
    currentUser: user,
    outbox: outbox,
  );
  final month = YearMonth.of(LocalDate.fromDateTime(example.now));
  final rubles = figmaHolidayCards[example.key]!.rubles;
  for (final MapEntry(key: day, value: amount) in rubles.entries) {
    await expenses.create(
      budgetId: budget.id,
      categoryId: category.id,
      amount: Money.rubles(amount),
      spentOn: month.dayOf(day),
    );
  }
}
