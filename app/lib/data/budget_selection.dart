import 'dart:async';

Stream<R> combineLatest<A, B, R>(
  Stream<A> first,
  Stream<B> second,
  R Function(A a, B b) combine,
) {
  late final StreamController<R> controller;
  StreamSubscription<A>? firstSub;
  StreamSubscription<B>? secondSub;
  late A lastFirst;
  late B lastSecond;
  var hasFirst = false;
  var hasSecond = false;
  var done = 0;

  void emit() {
    if (!hasFirst || !hasSecond) return;
    final R value;
    try {
      value = combine(lastFirst, lastSecond);
    } catch (e, st) {
      controller.addError(e, st);
      return;
    }
    controller.add(value);
  }

  void finished() {
    done++;
    if (done == 2) unawaited(controller.close());
  }

  controller = StreamController<R>(
    onListen: () {
      firstSub = first.listen(
        (value) {
          lastFirst = value;
          hasFirst = true;
          emit();
        },
        onError: controller.addError,
        onDone: finished,
      );
      secondSub = second.listen(
        (value) {
          lastSecond = value;
          hasSecond = true;
          emit();
        },
        onError: controller.addError,
        onDone: finished,
      );
    },
    onPause: () {
      firstSub?.pause();
      secondSub?.pause();
    },
    onResume: () {
      firstSub?.resume();
      secondSub?.resume();
    },
    onCancel: () => Future.wait([?firstSub?.cancel(), ?secondSub?.cancel()]),
  );
  return controller.stream;
}
