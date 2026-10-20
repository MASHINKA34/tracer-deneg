import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/core/clock.dart';
import 'package:milionchik/core/logging/provider_logger.dart';
import 'package:milionchik/data/db/app_database.dart';
import 'package:milionchik/data/providers.dart';
import 'package:shared/shared.dart';

final DateTime fixedNow = DateTime(2026, 10, 19, 18, 40);

final class ProviderHarness {
  ProviderHarness({List<Override> overrides = const []})
    : db = AppDatabase.memory() {
    Logger.root.level = Level.ALL;
    _logs = Logger.root.onRecord.listen(records.add);
    container = ProviderContainer.test(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(Clock(now: () => now)),
        ...overrides,
      ],
      observers: const [ProviderLogger()],
    );
    addTearDown(dispose);
  }

  final AppDatabase db;
  late final ProviderContainer container;
  final List<LogRecord> records = [];
  late final StreamSubscription<LogRecord> _logs;

  DateTime now = fixedNow;

  T read<T>(ProviderListenable<T> provider) => container.read(provider);

  Watched<T> watch<T>(ProviderListenable<AsyncValue<T>> provider) =>
      Watched<T>(container, provider);

  List<String> lines(String logger, [Level level = Level.ALL]) => [
    for (final r in records)
      if (r.loggerName == logger && r.level >= level) formatLogRecord(r),
  ];

  Future<void> dispose() async {
    container.dispose();
    await _logs.cancel();
    await db.close();
  }
}

final class Watched<T> {
  Watched(ProviderContainer container, ProviderListenable<AsyncValue<T>> p) {
    _subscription = container.listen<AsyncValue<T>>(p, (_, next) {
      values.add(next);
      _changes.add(null);
    }, fireImmediately: true);
    addTearDown(close);
  }

  final List<AsyncValue<T>> values = [];
  final StreamController<void> _changes = StreamController<void>.broadcast();
  late final ProviderSubscription<AsyncValue<T>> _subscription;

  AsyncValue<T> get last => values.last;

  Future<AsyncValue<T>> until(
    bool Function(AsyncValue<T> value) test, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (!test(values.last)) {
      final left = deadline.difference(DateTime.now());
      if (left <= Duration.zero) {
        throw TimeoutException('no matching value, got $values', timeout);
      }
      await _changes.stream.first.timeout(left, onTimeout: () {});
    }
    return values.last;
  }

  Future<T> data([bool Function(T value)? test]) async {
    final value = await until(
      (v) => v is AsyncData<T> && (test == null || test(v.value)),
    );
    return value.requireValue;
  }

  Future<Object> error() async {
    final value = await until((v) => v is AsyncError<T>);
    return value.error!;
  }

  void close() {
    _subscription.close();
    _changes.close();
  }
}
