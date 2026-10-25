import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/core/auth_gate.dart';
import 'package:milionchik/core/clock.dart';
import 'package:milionchik/core/widget_triggers_scope.dart';
import 'package:milionchik/data/current_user.dart';
import 'package:milionchik/data/db/app_database.dart';
import 'package:milionchik/data/providers.dart';
import 'package:milionchik/data/repositories/expenses_repository.dart';
import 'package:milionchik/data/repositories/outbox_queue.dart';
import 'package:milionchik/data/session/session.dart';
import 'package:milionchik/data/session/session_providers.dart';
import 'package:milionchik/data/session/session_state.dart';
import 'package:milionchik/data/session/session_store.dart';
import 'package:milionchik/features/holidays/mood_controller.dart';
import 'package:milionchik/features/widget/home_widget_store.dart';
import 'package:milionchik/features/widget/widget_updater.dart';
import 'package:shared/shared.dart';

import '../../data/api/fake_api_adapter.dart' show LogCapture;
import '../../data/session/fake_secure_values.dart';
import '../../data/sync/pull_fixture.dart' show serverExpense;
import '../../data/sync/sync_triggers_fixture.dart';
import '../../support/app_scope.dart';
import '../profile/profile_fixture.dart';
import '../profile/profile_harness.dart' show ProfileHarness;

final class WidgetWrite {
  WidgetWrite(this.at, this.text);

  final Duration? at;
  final String text;

  Map<String, Object?> get json => jsonDecode(text) as Map<String, Object?>;

  String get state => json['state']! as String;

  String? get total => json['total'] as String?;

  String? get today => json['today'] as String?;

  String? get emoji => json['emoji'] as String?;

  String? get month => json['month'] as String?;

  String get theme => json['theme']! as String;

  String get mood => json['mood']! as String;
}

final class FakeWidgetStorage implements HomeWidgetStorage {
  FakeWidgetStorage({this.now});

  final Duration Function()? now;
  final List<WidgetWrite> writes = [];
  final List<String> redraws = [];
  Completer<void>? gate;
  Object? saveError;
  Object? redrawError;
  int _active = 0;
  int maxActive = 0;

  WidgetWrite get last => writes.last;

  @override
  Future<bool?> save(String key, String value) async {
    _active++;
    maxActive = math.max(maxActive, _active);
    try {
      final waiting = gate;
      if (waiting != null) await waiting.future;
      final error = saveError;
      if (error != null) throw error;
      writes.add(WidgetWrite(now?.call(), value));
      return true;
    } finally {
      _active--;
    }
  }

  @override
  Future<bool?> redraw(String qualifiedAndroidName) async {
    final error = redrawError;
    if (error != null) throw error;
    redraws.add(qualifiedAndroidName);
    return true;
  }
}

final RegExp _updated = RegExp(r'widget updated reason=(.+?) state=');

List<String> widgetReasons(List<LogRecord> records) => [
  for (final r in records)
    if (r.loggerName == 'widget' && r.level == Level.INFO)
      ?_updated.firstMatch(r.message)?.group(1),
];

const String otherPhoneExpenseId = 'exp-widget-other-phone';

Map<String, Object?> widgetMeReply() => {
  'id': profileUserId,
  'login': 'anya_m',
  'displayName': 'Аня',
  'birthdayMonth': null,
  'birthdayDay': null,
  'holidaysEnabled': true,
  'holidaysDisabled': const <String>[],
  'createdAt': '2026-10-01T09:00:00.000Z',
};

Future<void> seedWidgetExpenses(AppDatabase db) =>
    DriftExpensesRepository(
      db,
      currentUser: const SessionCurrentUser(profileUserId),
      outbox: DriftOutboxQueue(db),
    ).applyFromServer([
      serverExpense(
        id: 'exp-widget-today',
        budgetId: profilePersonalId,
        categoryId: 'cat-personal-0',
        kopecks: 64000,
        seq: 1,
      ),
      serverExpense(
        id: 'exp-widget-oct-3',
        budgetId: profilePersonalId,
        categoryId: 'cat-personal-1',
        kopecks: 150000,
        spentOn: LocalDate(2026, 10, 3),
        seq: 2,
      ),
      serverExpense(
        id: 'exp-widget-sep',
        budgetId: profilePersonalId,
        categoryId: 'cat-personal-1',
        kopecks: 99900,
        spentOn: LocalDate(2026, 9, 30),
        seq: 3,
      ),
      serverExpense(
        id: 'exp-widget-family',
        budgetId: profileFamilyId,
        categoryId: 'cat-family-0',
        kopecks: 30000,
        seq: 4,
      ),
    ]);

final class WidgetRig {
  WidgetRig(this.tester);

  final WidgetTester tester;
  late final VirtualTime time = VirtualTime(settle: settle);
  late final FakeWidgetStorage storage = FakeWidgetStorage(
    now: () => time.now,
  );
  late final AppDatabase db = openTestDatabase();
  final FakeSecureValues secure = FakeSecureValues();
  late final LogCapture logs = LogCapture();

  static const Key _child = Key('widget-rig-child');

  ProviderContainer get container =>
      ProviderScope.containerOf(tester.element(find.byKey(_child)));

  List<String> get reasons => widgetReasons(logs.records);

  Future<void> mount({
    List<Override> overrides = const [],
    bool signedIn = true,
    LocalDate? today,
  }) async {
    addTearDown(logs.dispose);
    await tester.runAsync(() async {
      await ProfileFixture.mockup(db);
      await seedWidgetExpenses(db);
      if (signedIn) {
        await SessionStore(
          secure,
        ).save(const Session(user: profileUser, tokens: ProfileHarness.tokens));
      }
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          todayOverrideProvider.overrideWithBuild(
            (ref, _) => today ?? LocalDate(2026, 10, 19),
          ),
          secureValuesProvider.overrideWithValue(secure),
          if (signedIn)
            sessionProvider.overrideWithBuild(
              (ref, _) => const SessionActive(profileUser),
            ),
          signInRequiredProvider.overrideWithValue(true),
          homeWidgetStoreProvider.overrideWithValue(HomeWidgetStore(storage)),
          widgetUpdateTimerProvider.overrideWithValue(time.start),
          moodTimerProvider.overrideWithValue(time.start),
          ...overrides,
        ],
        child: const WidgetTriggersScope(child: SizedBox(key: _child)),
      ),
    );
    await settle();
    await time.elapse(WidgetUpdater.maxDelay);
  }

  Future<void> settle() async {
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<T> act<T>(Future<T> Function(ProviderContainer container) body) async {
    final result = await tester.runAsync(() => body(container));
    await settle();
    return result as T;
  }
}
