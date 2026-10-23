import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/core/clock.dart';
import 'package:milionchik/data/api/api_providers.dart';
import 'package:milionchik/data/db/app_database.dart';
import 'package:milionchik/data/providers.dart';
import 'package:milionchik/data/session/session.dart';
import 'package:milionchik/data/session/session_providers.dart';
import 'package:milionchik/data/session/session_state.dart';
import 'package:milionchik/data/sync/pull_controller.dart';
import 'package:milionchik/data/sync/pull_service.dart';
import 'package:shared/shared.dart';

import '../api/fake_api_adapter.dart';
import 'pull_fixture.dart';

const _user = SessionUser(
  userId: pullUserId,
  login: 'anya_m',
  displayName: 'Аня',
);

void main() {
  late LogCapture logs;
  late AppDatabase db;

  setUp(() {
    logs = LogCapture();
    db = AppDatabase.memory();
  });

  tearDown(() async {
    await logs.dispose();
    await db.close();
  });

  final personal = serverPersonal();

  FakePullServer server() => FakePullServer([
    SyncPullResponse(
      budgets: [personal],
      categories: serverPresets(personal.id),
      cursor: 12,
      hasMore: true,
    ),
    SyncPullResponse(
      members: [ownerOf(personal.id)],
      cursor: 13,
      hasMore: false,
    ),
  ]);

  ProviderContainer container(FakePullServer server, {bool signedIn = true}) {
    final c = ProviderContainer.test(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(
          Clock(now: () => DateTime.utc(2026, 10, 19, 15, 40)),
        ),
        apiClientProvider.overrideWith((ref) => pullApiClient(server)),
        if (signedIn)
          sessionProvider.overrideWithBuild(
            (ref, _) => const SessionActive(_user),
          ),
      ],
    );
    return c;
  }

  test('два запуска подряд: один проход по страницам, второй ждёт первый и '
      'получает тот же результат', () async {
    final fake = server();
    final gate = Completer<void>();
    fake.before[1] = (call) async {
      await gate.future;
      return null;
    };
    final c = container(fake);
    final pull = c.read(pullControllerProvider.notifier);

    final first = pull.run(PullReason.login);
    final second = pull.run(PullReason.manual);
    expect(c.read(pullControllerProvider), isA<PullRunning>());
    expect(c.read(pullControllerProvider).showsIndicator, isTrue);
    gate.complete();
    final results = await Future.wait([first, second]);

    expect(fake.cursors, [0, 12]);
    expect(identical(results[0], results[1]), isTrue);
    expect(results[0]!.cursorAfter, 13);
    expect(c.read(pullControllerProvider), isA<PullIdle>());
    expect(
      logs.linesOf('sync', Level.FINE),
      contains(
        endsWith('pull reason=manual joins the running pull reason=login'),
      ),
    );

    await pull.run(PullReason.manual);
    expect(fake.cursors, [0, 12, 13]);
  });

  test('без сессии: pull не идёт на сервер, запрошенная первая загрузка '
      'снимается', () async {
    final fake = server();
    final c = container(fake, signedIn: false);
    final pull = c.read(pullControllerProvider.notifier);

    pull.requestAfterSignIn(PullReason.login);
    expect(await pull.startRequested(), isNull);

    expect(fake.adapter.calls, isEmpty);
    expect(c.read(pullControllerProvider), isA<PullIdle>());
    expect(
      logs.linesOf('sync', Level.INFO),
      contains(
        endsWith(
          'pull skipped reason=login: session absent, nothing to load from '
          'the server',
        ),
      ),
    );
  });

  test('первая загрузка после входа ждёт главную: до startRequested '
      'запросов нет, индикатор уже виден; запуск один раз', () async {
    final fake = server();
    final c = container(fake);
    final pull = c.read(pullControllerProvider.notifier);

    pull.requestAfterSignIn(PullReason.register);

    expect(c.read(pullControllerProvider), isA<PullPending>());
    expect(c.read(pullControllerProvider).showsIndicator, isTrue);
    expect(fake.adapter.calls, isEmpty);

    final result = await pull.startRequested();
    expect(result!.reason, PullReason.register);
    expect(await pull.startRequested(), isNull);
    expect(fake.cursors, [0, 12]);
    expect(
      logs.linesOf('sync', Level.INFO),
      containsAllInOrder([
        endsWith(
          'initial pull requested reason=register → starts when the main '
          'screen opens',
        ),
        matches(RegExp(r'pull done reason=register pages=2 .*cursor=0→13')),
      ]),
    );
  });

  test('ошибки подряд: номер попытки растёт, у каждой ошибки свой номер '
      'для снекбара, успех сбрасывает счёт', () async {
    final fake = server();
    var down = true;
    fake.before[1] = (call) =>
        down ? throw const SocketException('Network is unreachable') : null;
    final c = container(fake);
    final pull = c.read(pullControllerProvider.notifier);

    expect(await pull.run(PullReason.login), isNull);
    final first = c.read(pullControllerProvider) as PullFailed;
    expect(first.failure.attempt, 1);
    expect(c.read(pullControllerProvider).showsIndicator, isFalse);
    expect(pull.claimFailureNotice(first.id), isTrue);
    expect(pull.claimFailureNotice(first.id), isFalse);

    expect(await pull.run(PullReason.retry), isNull);
    final second = c.read(pullControllerProvider) as PullFailed;
    expect(second.failure.attempt, 2);
    expect(second.id, greaterThan(first.id));
    expect(pull.claimFailureNotice(second.id), isTrue);

    down = false;
    expect(await pull.run(PullReason.retry), isNotNull);
    expect(c.read(pullControllerProvider), isA<PullIdle>());

    down = true;
    await db
        .update(db.syncStates)
        .write(const SyncStatesCompanion(cursor: Value(0)));
    await pull.run(PullReason.manual);
    expect((c.read(pullControllerProvider) as PullFailed).failure.attempt, 1);
    expect(
      logs.linesOf('sync', Level.WARNING),
      containsAllInOrder([
        contains(
          'pull failed reason=login stage=request page=1 cursor=0 '
          'attempt=1 ApiNetworkFailure',
        ),
        contains(
          'pull failed reason=retry stage=request page=1 cursor=0 '
          'attempt=2 ApiNetworkFailure',
        ),
        contains(
          'pull failed reason=manual stage=request page=1 cursor=0 '
          'attempt=1 ApiNetworkFailure',
        ),
      ]),
    );
  });
}
