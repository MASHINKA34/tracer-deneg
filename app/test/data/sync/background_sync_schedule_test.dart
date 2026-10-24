import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/data/sync/background_job.dart';
import 'package:milionchik/data/sync/background_sync.dart';

import '../api/fake_api_adapter.dart';
import 'background_sync_fixture.dart';

final class _Rig {
  final FakeScheduler scheduler = FakeScheduler();
  int queue = 0;
  late final BackgroundSync sync = BackgroundSync(
    scheduler: scheduler,
    queueSize: () async => queue,
    job: () => throw StateError('job is not run in these tests'),
  );
}

void main() {
  late LogCapture logs;

  setUp(() => logs = LogCapture());
  tearDown(() => logs.dispose());

  test('старт с сессией: периодическая задача раз в 30 минут с требованием '
      'сети', () async {
    final rig = _Rig();

    rig.sync.start(signedIn: true, foreground: true);
    await rig.sync.idle;

    expect(rig.scheduler.calls, ['schedule $periodicSyncUniqueName']);
    final request = rig.scheduler.scheduled.single;
    expect(request.task, periodicSyncTask);
    expect(request.frequency, const Duration(minutes: 30));
    expect(request.requiresNetwork, isTrue);
    expect(
      logs.linesOf('bg', Level.INFO).last,
      contains(
        'background task scheduled BackgroundTaskRequest('
        'ru.milionchik.sync.periodic task=sync-periodic every 30min '
        'network=connected) (app started with a session) in',
      ),
    );
  });

  test('старт без сессии: обе задачи отменяются', () async {
    final rig = _Rig();

    rig.sync.start(signedIn: false, foreground: true);
    await rig.sync.idle;

    expect(rig.scheduler.calls, [
      'cancel $periodicSyncUniqueName',
      'cancel $pendingSyncUniqueName',
    ]);
  });

  test('выход из аккаунта (сессия active → absent): обе задачи отменены; '
      'вход снова - периодическая опять в расписании', () async {
    final rig = _Rig();
    rig.sync.start(signedIn: true, foreground: true);

    rig.sync.sessionChanged(active: false, change: 'active→absent');
    await rig.sync.idle;
    expect(rig.scheduler.calls, [
      'schedule $periodicSyncUniqueName',
      'cancel $periodicSyncUniqueName',
      'cancel $pendingSyncUniqueName',
    ]);
    expect(
      logs.linesOf('bg', Level.INFO).last,
      contains(
        'background tasks cancelled ru.milionchik.sync.periodic, '
        'ru.milionchik.sync.pending (session active→absent: signed out, '
        'account deleted or session ended) in',
      ),
    );

    rig.sync.sessionChanged(active: true, change: 'absent→active');
    await rig.sync.idle;
    expect(rig.scheduler.calls.last, 'schedule $periodicSyncUniqueName');
  });

  test('ушли в фон с очередью 3: разовая задача с сетью; с пустой очередью '
      '- задачи нет', () async {
    final rig = _Rig()..queue = 3;
    rig.sync.start(signedIn: true, foreground: true);

    rig.sync.paused();
    await rig.sync.idle;

    final once = rig.scheduler.scheduled.last;
    expect(once.uniqueName, pendingSyncUniqueName);
    expect(once.task, pendingSyncTask);
    expect(once.periodic, isFalse);
    expect(once.requiresNetwork, isTrue);
    expect(once.reason, 'app went to background with 3 unsent change(s)');

    rig.queue = 0;
    rig.sync.resumed();
    rig.sync.paused();
    await rig.sync.idle;
    expect(
      rig.scheduler.calls.where((c) => c == 'schedule $pendingSyncUniqueName'),
      hasLength(1),
    );
    expect(
      logs.linesOf('bg', Level.FINE).last,
      endsWith(
        'background sync: app went to background, queue empty → no one-off '
        'task',
      ),
    );
  });

  test('запись в очередь в фоне - разовая задача; на экране - нет', () async {
    final rig = _Rig()..queue = 1;
    rig.sync.start(signedIn: true, foreground: true);

    rig.sync.outboxWritten();
    await rig.sync.idle;
    expect(rig.scheduler.calls, ['schedule $periodicSyncUniqueName']);

    rig.queue = 0;
    rig.sync.paused();
    rig.queue = 2;
    rig.sync.outboxWritten();
    await rig.sync.idle;
    expect(
      rig.scheduler.scheduled.last.reason,
      'change queued while the app is in background with 2 unsent change(s)',
    );
  });

  test('без сессии в фон с очередью - разовой задачи нет', () async {
    final rig = _Rig()..queue = 4;
    rig.sync.start(signedIn: false, foreground: true);

    rig.sync.paused();
    await rig.sync.idle;

    expect(rig.scheduler.calls.where((c) => c.startsWith('schedule')), isEmpty);
  });

  test(
    'workmanager недоступен: warn с причиной, приложение не падает',
    () async {
      final rig = _Rig()..scheduler.failWith = StateError('no plugin');

      rig.sync.start(signedIn: true, foreground: true);
      await rig.sync.idle;
      rig.sync.sessionChanged(active: false, change: 'active→absent');
      await rig.sync.idle;

      final warnings = logs.linesOf('bg', Level.WARNING);
      expect(warnings, hasLength(2));
      expect(
        warnings.first,
        contains(
          'background sync: schedule sync-periodic failed: StateError: Bad state: '
          'no plugin',
        ),
      );
      expect(
        warnings.last,
        contains('background sync: cancel background tasks failed'),
      );
    },
  );
}
