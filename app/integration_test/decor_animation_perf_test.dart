import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/app.dart';
import 'package:milionchik/core/clock.dart';
import 'package:milionchik/core/logging/app_logging.dart';
import 'package:milionchik/data/current_user.dart';
import 'package:milionchik/data/db/app_database.dart';
import 'package:milionchik/data/providers.dart';
import 'package:milionchik/data/repositories/budgets_repository.dart';
import 'package:milionchik/data/repositories/categories_repository.dart';
import 'package:milionchik/data/repositories/expenses_repository.dart';
import 'package:milionchik/data/repositories/outbox_queue.dart';
import 'package:milionchik/data/repositories/prefs_repository.dart';
import 'package:milionchik/ui/components/month_card.dart';
import 'package:shared/shared.dart';

final _log = Logger('it');

final DateTime _now = DateTime(2026, 12, 29, 18, 40);

const Map<int, int> _december = {
  1: 300, 2: 3310, 3: 2290, 5: 310, 7: 1420, 11: 620, 12: 180, 14: 2140, //
  15: 1610, 16: 670, 17: 550, 19: 1850, 20: 1520, 21: 720, 22: 570, //
  23: 1850, 24: 490, 25: 120, 26: 450, 28: 1370, 29: 160,
};

const Duration _animatedWindow = Duration(seconds: 10);
const Duration _staticWindow = Duration(seconds: 5);
const Duration _timingsFlush = Duration(seconds: 2);

Future<void> _seedDecember(AppDatabase db) async {
  final user = LocalPrefsCurrentUser(DriftPrefsRepository(db));
  final outbox = DriftOutboxQueue(db);
  final budget = await DriftBudgetsRepository(
    db,
    currentUser: user,
    outbox: outbox,
  ).createLocalPersonal();
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
  final month = YearMonth.of(LocalDate.fromDateTime(_now));
  for (final MapEntry(key: day, value: rubles) in _december.entries) {
    await expenses.create(
      budgetId: budget.id,
      categoryId: category.id,
      amount: Money.rubles(rubles),
      spentOn: month.dayOf(day),
    );
  }
}

Future<int> _maxTickers(Duration window) async {
  var most = 0;
  final sw = Stopwatch()..start();
  while (sw.elapsed < window) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final now = SchedulerBinding.instance.transientCallbackCount;
    if (now > most) most = now;
  }
  return most;
}

Future<Map<String, dynamic>> _framesDuring(Duration window) async {
  final timings = <ui.FrameTiming>[];
  final sw = Stopwatch()..start();
  SchedulerBinding.instance.addTimingsCallback(timings.addAll);
  final tickers = await _maxTickers(window);
  await Future<void>.delayed(_timingsFlush);
  SchedulerBinding.instance.removeTimingsCallback(timings.addAll);
  return {
    if (timings.isNotEmpty) ...FrameTimingSummarizer(timings).summary,
    'frame_count': timings.length,
    'tickers_max': tickers,
    'seconds': sw.elapsedMilliseconds / 1000,
  };
}

String _brief(Map<String, dynamic> s) =>
    'frames=${s['frame_count']} in ${s['seconds']}s '
    'build avg=${s['average_frame_build_time_millis']}ms '
    'p90=${s['90th_percentile_frame_build_time_millis']}ms '
    'p99=${s['99th_percentile_frame_build_time_millis']}ms '
    'worst=${s['worst_frame_build_time_millis']}ms '
    'missed=${s['missed_frame_build_budget_count']}; '
    'raster avg=${s['average_frame_rasterizer_time_millis']}ms '
    'p90=${s['90th_percentile_frame_rasterizer_time_millis']}ms '
    'p99=${s['99th_percentile_frame_rasterizer_time_millis']}ms '
    'worst=${s['worst_frame_rasterizer_time_millis']}ms '
    'missed=${s['missed_frame_rasterizer_budget_count']}; '
    'tickers max=${s['tickers_max']}';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('главная на Новый год: время кадров при анимации декора и '
      'тишина при выключенных анимациях', (tester) async {
    final logging = AppLogging.start(extraSink: debugPrint);
    addTearDown(logging.dispose);
    final total = Stopwatch()..start();
    _log.info(
      'decor perf start: mode=${kProfileMode ? 'profile' : 'debug'} '
      'clock=$_now lifecycle=${binding.lifecycleState?.name ?? '-'}',
    );

    final db = AppDatabase.memory();
    addTearDown(db.close);
    final seed = Stopwatch()..start();
    await _seedDecember(db);
    _log.info(
      'decor perf seed: December 2026 expenses=${_december.length} '
      'in ${seed.elapsedMilliseconds}ms',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          clockProvider.overrideWithValue(Clock(now: () => _now)),
        ],
        child: MilionchikApp(today: LocalDate.fromDateTime(_now)),
      ),
    );
    for (var i = 0; i < 50 && find.byType(MonthCard).evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final card = tester.widget<MonthCard>(find.byType(MonthCard));
    expect(card.mood, Mood.newyear);
    await Future<void>.delayed(const Duration(seconds: 2));
    _log.info(
      'decor perf: main screen shown month=${card.month} mood=newyear, '
      'measuring ${_animatedWindow.inSeconds}s of decor animation',
    );

    final animated = await _framesDuring(_animatedWindow);
    binding.reportData = {...?binding.reportData, 'newyear_animated': animated};
    _log.info('decor perf animated: ${_brief(animated)}');
    expect(animated['tickers_max'], greaterThanOrEqualTo(1));

    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await Future<void>.delayed(const Duration(seconds: 1));
    final still = await _framesDuring(_staticWindow);
    binding.reportData = {...?binding.reportData, 'animations_disabled': still};
    _log.info(
      'decor perf animations disabled: ${_brief(still)} (frames come from '
      'the test binding, it schedules one after every frame)',
    );
    expect(still['tickers_max'], 0);

    _log.info('decor perf passed in ${total.elapsedMilliseconds}ms');
  });
}
