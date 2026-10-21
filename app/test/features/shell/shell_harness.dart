import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/app.dart';
import 'package:milionchik/data/db/app_database.dart';
import 'package:milionchik/ui/components/bottom_nav.dart';
import 'package:shared/shared.dart';

import '../../support/app_scope.dart';

final class ShellHarness {
  ShellHarness._(this.tester, this.db);

  final WidgetTester tester;
  final AppDatabase db;
  final List<LogRecord> records = [];
  final List<MethodCall> platformCalls = [];

  static Future<ShellHarness> start(
    WidgetTester tester, {
    Size size = const Size(360, 800),
    double bottomInset = 0,
    double topInset = 0,
    AppDatabase? db,
    DateTime? now,
  }) async {
    final harness = ShellHarness._(tester, db ?? openTestDatabase());
    final previousLevel = Logger.root.level;
    Logger.root.level = Level.ALL;
    final sub = Logger.root.onRecord.listen(harness.records.add);
    addTearDown(() async {
      await sub.cancel();
      Logger.root.level = previousLevel;
    });

    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = size
      ..viewPadding = FakeViewPadding(top: topInset, bottom: bottomInset)
      ..padding = FakeViewPadding(top: topInset, bottom: bottomInset);
    addTearDown(tester.view.reset);

    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        harness.platformCalls.add(call);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(
      withDatabase(
        harness.db,
        MilionchikApp(today: LocalDate.fromDateTime(now ?? testNow)),
        now: now,
      ),
    );
    await tester.pumpAndSettle();
    return harness;
  }

  Iterable<String> navDebug() => records
      .where((r) => r.loggerName == 'nav' && r.level == Level.FINE)
      .map((r) => r.message);

  AppNavTab get activeTab =>
      tester.widget<AppBottomNav>(find.byType(AppBottomNav)).active;

  Finder navLabel(String label) => find.descendant(
    of: find.byType(AppBottomNav),
    matching: find.text(label),
  );

  Future<void> tapTab(String label) async {
    await tester.tap(navLabel(label));
    await tester.pumpAndSettle();
  }

  Future<void> tapPlus() async {
    await tester.tap(find.bySemanticsLabel('Добавить трату'));
    await tester.pumpAndSettle();
  }

  Future<void> systemBack() async {
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
  }

  Future<void> predictiveBackGesture() async {
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

  int get systemPops =>
      platformCalls.where((c) => c.method == 'SystemNavigator.pop').length;

  bool? get frameworkHandlesBack => platformCalls
      .where((c) => c.method == 'SystemNavigator.setFrameworkHandlesBack')
      .map((c) => c.arguments as bool)
      .lastOrNull;
}
