import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milionchik/app.dart';
import 'package:milionchik/core/data_startup.dart';
import 'package:milionchik/data/api/token_store.dart';
import 'package:milionchik/data/db/app_database.dart';
import 'package:milionchik/data/repositories/budgets_repository.dart';
import 'package:milionchik/data/session/session.dart';
import 'package:milionchik/data/sync/background_job.dart';
import 'package:milionchik/features/widget/home_widget_data.dart';
import 'package:milionchik/features/widget/widget_updater.dart';

import '../data/api/fake_api_adapter.dart' show LogCapture;
import '../support/app_scope.dart';

const _session = Session(
  user: SessionUser(
    userId: 'user-widget-root-1',
    login: 'widget_user',
    displayName: 'Виджет',
  ),
  tokens: AuthTokens(
    accessToken: 'ACCESS-widget-root',
    refreshToken: 'REFRESH-widget-root',
  ),
);

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testWidgets('приложение со входом: на старте данные виджета уходят в '
      'home_widget и просится перерисовка; хук фоновой задачи - этот же '
      'обновитель', (tester) async {
    final logs = LogCapture();
    addTearDown(logs.dispose);
    tester.view
      ..devicePixelRatio = 2
      ..physicalSize = const Size(360, 800) * 2;
    addTearDown(tester.view.reset);
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('home_widget'),
      (call) async {
        calls.add(call);
        return true;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('home_widget'),
        null,
      ),
    );
    final db = AppDatabase.memory();
    final data = await tester.runAsync(() async {
      await testBudgets(db).createLocalPersonal();
      return startData(open: () async => db, readSession: () async => _session);
    });

    await tester.pumpWidget(appRoot(data!));
    for (var i = 0; i < 12 && calls.length < 2; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 500));
    }

    expect([for (final c in calls) c.method], [
      'saveWidgetData',
      'updateWidget',
    ]);
    final saved = calls.first.arguments as Map<Object?, Object?>;
    expect(saved['id'], homeWidgetDataKey);
    final json = jsonDecode(saved['data']! as String) as Map<String, Object?>;
    expect(json['state'], 'month');
    expect(json['v'], homeWidgetDataVersion);
    expect(
      (calls[1].arguments as Map<Object?, Object?>)['qualifiedAndroidName'],
      homeWidgetAndroidProvider,
    );
    expect(
      logs.linesOf('widget').where((l) => l.contains('widget updated reason=')),
      hasLength(1),
    );

    final container = ProviderScope.containerOf(
      tester.element(find.byType(MilionchikApp)),
    );
    expect(
      container.read(homeWidgetUpdateProvider),
      container.read(widgetUpdaterProvider).updateNow,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
    await tester.runAsync(db.close);
  });
}
