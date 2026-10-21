import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/app.dart';
import 'package:milionchik/core/clock.dart';
import 'package:milionchik/core/logging/app_logging.dart';
import 'package:milionchik/core/logging/provider_logger.dart';
import 'package:milionchik/data/current_user.dart';
import 'package:milionchik/data/db/app_database.dart';
import 'package:milionchik/data/dev_seed.dart';
import 'package:milionchik/data/providers.dart';
import 'package:milionchik/data/repositories/prefs_repository.dart';
import 'package:milionchik/features/month/day_sheet.dart';
import 'package:milionchik/features/month/month_picker_sheet.dart';
import 'package:milionchik/features/month/month_screen.dart';
import 'package:milionchik/features/month/today_block.dart';
import 'package:shared/shared.dart';

final _log = Logger('it');

final DateTime _now = DateTime(2026, 10, 19, 18, 40);

const int _steps = 6;

Future<void> _backGesture(WidgetTester tester) async {
  final codec = SystemChannels.backGesture.codec;
  Future<void> send(MethodCall call) =>
      tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        SystemChannels.backGesture.name,
        codec.encodeMethodCall(call),
        (_) {},
      );
  await send(
    const MethodCall('startBackGesture', <String, Object?>{
      'touchOffset': <double>[4, 400],
      'progress': 0.0,
      'swipeEdge': 0,
    }),
  );
  await send(
    const MethodCall('updateBackGestureProgress', <String, Object?>{
      'touchOffset': <double>[120, 400],
      'progress': 0.6,
      'swipeEdge': 0,
    }),
  );
  await send(const MethodCall('commitBackGesture'));
  await tester.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('главная → выбор месяца → сентябрь → назад к октябрю → шторка '
      'дня → жест «назад»', (tester) async {
    final logging = AppLogging.start(extraSink: debugPrint);
    addTearDown(logging.dispose);
    final total = Stopwatch()..start();
    var step = 0;

    Future<void> run(String what, Future<void> Function() body) async {
      step++;
      final sw = Stopwatch()..start();
      try {
        await body();
      } catch (e, st) {
        _log.severe(
          'step $step/$_steps "$what" failed after '
          '${sw.elapsedMilliseconds}ms: ${describeError(e)}',
          e,
          st,
        );
        rethrow;
      }
      _log.info('step $step/$_steps $what in ${sw.elapsedMilliseconds}ms');
    }

    _log.info(
      'scenario start: in-memory database with dev seed October 2026, '
      'clock $_now',
    );
    final db = AppDatabase.memory();
    addTearDown(db.close);

    await run('main screen October 2026, today cell with full TalkBack '
        'label', () async {
      final seed = await DevSeed(
        db,
        currentUser: LocalPrefsCurrentUser(DriftPrefsRepository(db)),
      ).runIfRequested(flag: 'true', debugBuild: true);
      expect(seed.status, DevSeedStatus.seeded);
      _log.info(
        'dev seed ${seed.status.name} budgets=${seed.budgets} '
        'expenses=${seed.expenses}',
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            clockProvider.overrideWithValue(Clock(now: () => _now)),
          ],
          observers: const [ProviderLogger()],
          child: MilionchikApp(today: LocalDate.fromDateTime(_now)),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsLabel('Октябрь 2026, выбрать месяц'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          '19 октября, потрачено 1${nbsp}100 рублей, сегодня',
        ),
        findsOneWidget,
      );
      expect(find.byType(TodayBlock), findsOneWidget);
    });

    await run('month picker opened by title tap', () async {
      await tester.tap(find.bySemanticsLabel('Октябрь 2026, выбрать месяц'));
      await tester.pumpAndSettle();
      expect(find.byType(MonthPicker), findsOneWidget);
      expect(find.text('Выбор месяца'), findsOneWidget);
    });

    await run('September chosen in picker and shown on main screen', () async {
      await tester.tap(find.bySemanticsLabel('Сентябрь 2026'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Открыть сентябрь'));
      await tester.pumpAndSettle();
      expect(find.byType(MonthPicker), findsNothing);
      expect(
        find.bySemanticsLabel('Сентябрь 2026, выбрать месяц'),
        findsOneWidget,
      );
      expect(find.byType(TodayBlock), findsNothing);
    });

    await run('back to October by › arrow', () async {
      await tester.tap(find.bySemanticsLabel('Следующий месяц'));
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsLabel('Октябрь 2026, выбрать месяц'),
        findsOneWidget,
      );
      expect(find.byType(TodayBlock), findsOneWidget);
    });

    await run('day sheet 17 October opened by cell tap', () async {
      await tester.tap(find.bySemanticsLabel(RegExp('^17 октября')));
      await tester.pumpAndSettle();
      expect(find.byType(DaySheet), findsOneWidget);
      expect(find.text('Суббота, 17 октября'), findsOneWidget);
    });

    await run('day sheet closed by back gesture, still on October', () async {
      await _backGesture(tester);
      expect(find.byType(DaySheet), findsNothing);
      expect(find.byType(MonthScreen), findsOneWidget);
      expect(
        find.bySemanticsLabel('Октябрь 2026, выбрать месяц'),
        findsOneWidget,
      );
    });

    _log.info('scenario passed in ${total.elapsedMilliseconds}ms');
  });
}
