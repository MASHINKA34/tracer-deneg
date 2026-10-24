import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milionchik/data/sync/sync_engine.dart';
import 'package:milionchik/features/month/month_header.dart';
import 'package:milionchik/features/month/sync_status_popover.dart';
import 'package:milionchik/ui/icons/app_icon.dart';
import 'package:shared/shared.dart';

import '../../data/api/fake_api_adapter.dart';
import '../profile/profile_harness.dart';

enum ServerMode { online, offline, down }

final class SyncStatusServer {
  ServerMode mode = ServerMode.online;
  Completer<void>? pushGate;
  Completer<void>? pullGate;
  final List<String> calls = [];
  int _cursor = 40;

  Future<FakeReply> handle(FakeCall call) async {
    calls.add('${call.method} ${call.path}');
    if (mode == ServerMode.offline) {
      throw const SocketException('Network is unreachable');
    }
    if (mode == ServerMode.down) {
      return FakeReply.error(503, 'internal', 'Сервер недоступен');
    }
    if (call.path.endsWith('/sync/push')) {
      final gate = pushGate;
      if (gate != null) await gate.future;
      final changes = call.json['changes']! as List<Object?>;
      _cursor += changes.length;
      return FakeReply.json(200, {
        'applied': [
          for (final c in changes) (c! as Map<String, Object?>)['id'],
        ],
        'rejected': const <Object?>[],
        'cursor': _cursor,
      });
    }
    if (call.path.endsWith('/sync/pull')) {
      final gate = pullGate;
      if (gate != null) await gate.future;
      return FakeReply.json(
        200,
        SyncPullResponse(cursor: _cursor, hasMore: false).toJson(),
      );
    }
    throw StateError('unexpected ${call.method} ${call.path}');
  }

  int callsTo(String path) => calls.where((c) => c.endsWith(path)).length;
}

Future<ProfileHarness> startMonth(
  WidgetTester tester,
  SyncStatusServer server, {
  Size size = const Size(360, 800),
  double textScale = 1,
}) => ProfileHarness.start(
  tester,
  server: server.handle,
  size: size,
  textScale: textScale,
);

SyncEngine engineOf(ProfileHarness h) => h.container.read(syncEngineProvider);

Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() done, {
  String reason = 'condition not reached',
}) async {
  for (var i = 0; i < 100 && !done(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(done(), isTrue, reason: reason);
}

Future<SyncCycleResult> syncAndWait(ProfileHarness h, SyncReason reason) async {
  SyncCycleResult? result;
  unawaited(engineOf(h).sync(reason).then((r) => result = r));
  await pumpUntil(h.tester, () => result != null, reason: 'sync cycle');
  await h.tester.pump(const Duration(milliseconds: 20));
  return result!;
}

Finder headerSync(Pattern label) => find.descendant(
  of: find.byType(MonthHeader),
  matching: find.bySemanticsLabel(label),
);

Finder headerIcon(AppIcons icon) => find.descendant(
  of: find.byType(MonthHeaderView),
  matching: find.byWidgetPredicate((w) => w is AppIcon && w.icon == icon),
);

Finder get popover => find.byType(SyncStatusPopover);

Finder inPopover(Finder finder) =>
    find.descendant(of: popover, matching: finder);

Future<void> openPopover(WidgetTester tester, Pattern label) async {
  await tester.tap(headerSync(label));
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 30));
  }
}
