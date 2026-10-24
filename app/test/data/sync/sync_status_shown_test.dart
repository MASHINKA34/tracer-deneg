import 'package:flutter_test/flutter_test.dart';
import 'package:milionchik/data/sync/pull_controller.dart';
import 'package:milionchik/data/sync/pull_service.dart';
import 'package:milionchik/data/sync/sync_engine.dart';
import 'package:milionchik/data/sync/sync_status_view.dart';

SyncEngineState _engine(SyncPhase phase, {int queue = 0}) =>
    SyncEngineState(phase: phase, queueSize: queue);

const PullStatus _idle = PullIdle();

void main() {
  test('фаза движка → статус в шапке: нет работы - «Синхронизировано», нет '
      'сети - «Ждёт сети», ошибка - «Ошибка» (с очередью и без)', () {
    for (final queue in const [0, 3]) {
      for (final previous in [null, ...SyncShown.values]) {
        expect(
          shownSyncOf(
            _engine(SyncPhase.idle, queue: queue),
            _idle,
            previous: previous,
          ),
          SyncShown.done,
          reason: 'idle queue=$queue previous=$previous',
        );
        expect(
          shownSyncOf(
            _engine(SyncPhase.waitingNetwork, queue: queue),
            _idle,
            previous: previous,
          ),
          SyncShown.waiting,
          reason: 'waitingNetwork queue=$queue previous=$previous',
        );
        expect(
          shownSyncOf(
            _engine(SyncPhase.error, queue: queue),
            _idle,
            previous: previous,
          ),
          SyncShown.error,
          reason: 'error queue=$queue previous=$previous',
        );
      }
    }
  });

  test('«Отправляем…» — когда есть что отправить или после ошибки и без '
      'сети; фоновая загрузка при «Синхронизировано» не мигает', () {
    final sending = _engine(SyncPhase.sending);
    final sendingQueue = _engine(SyncPhase.sending, queue: 2);
    expect(shownSyncOf(sendingQueue, _idle), SyncShown.sending);
    expect(
      shownSyncOf(sendingQueue, _idle, previous: SyncShown.done),
      SyncShown.sending,
    );
    expect(shownSyncOf(sending, _idle), SyncShown.done);
    expect(
      shownSyncOf(sending, _idle, previous: SyncShown.done),
      SyncShown.done,
    );
    expect(
      shownSyncOf(sending, _idle, previous: SyncShown.loading),
      SyncShown.done,
    );
    for (final previous in const [
      SyncShown.error,
      SyncShown.waiting,
      SyncShown.sending,
    ]) {
      expect(
        shownSyncOf(sending, _idle, previous: previous),
        SyncShown.sending,
        reason: 'previous=$previous',
      );
    }
  });

  test('первая загрузка после входа важнее фазы движка; «потянуть вниз» '
      'индикатор в шапке не включает', () {
    for (final phase in SyncPhase.values) {
      expect(
        shownSyncOf(_engine(phase), const PullPending(PullReason.login)),
        SyncShown.loading,
        reason: 'pending phase=$phase',
      );
      expect(
        shownSyncOf(_engine(phase), const PullRunning(PullReason.register)),
        SyncShown.loading,
        reason: 'running phase=$phase',
      );
    }
    expect(
      shownSyncOf(
        _engine(SyncPhase.sending),
        const PullRunning(PullReason.manual),
        previous: SyncShown.done,
      ),
      SyncShown.done,
    );
  });
}
