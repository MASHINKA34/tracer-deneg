import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/app.dart';
import 'package:milionchik/core/system_ui.dart';

import 'support/app_scope.dart';

void main() {
  late List<LogRecord> records;
  late StreamSubscription<LogRecord> subscription;

  setUp(() {
    records = [];
    Logger.root.level = Level.ALL;
    subscription = Logger.root.onRecord.listen(records.add);
  });
  tearDown(() => subscription.cancel());

  testWidgets('заглушка «Милиончик» и лог перехода на экран', (tester) async {
    await tester.pumpWidget(
      withDatabase(openTestDatabase(), const MilionchikApp()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Милиончик'), findsOneWidget);
    expect(
      records.where((r) => r.loggerName == 'nav').map((r) => r.message),
      contains(startsWith('push month')),
    );
  });

  testWidgets('системные панели прозрачные, иконки по теме', (tester) async {
    await tester.pumpWidget(
      withDatabase(openTestDatabase(), const MilionchikApp()),
    );
    await tester.pumpAndSettle();

    final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
      find.byType(AnnotatedRegion<SystemUiOverlayStyle>).first,
    );
    expect(region.value.statusBarColor, Colors.transparent);
    expect(region.value.systemNavigationBarColor, Colors.transparent);
    expect(region.value.statusBarIconBrightness, Brightness.dark);
  });

  test('тёмная тема — светлые иконки', () {
    final style = systemUiStyleFor(Brightness.dark);
    expect(style.statusBarIconBrightness, Brightness.light);
    expect(style.systemNavigationBarIconBrightness, Brightness.light);
  });
}
