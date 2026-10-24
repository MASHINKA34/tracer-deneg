import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milionchik/core/logging/error_handlers.dart';
import 'package:milionchik/core/logging/error_reports.dart';

import '../../data/api/fake_api_adapter.dart';

const String _rethrown = 'rethrown by ProviderException at:';

const String _comment = 'kommentariy-uniform-victor-whiskey';

final StackTrace _outer = StackTrace.fromString(
  '#0      _outerRethrowSite (package:milionchik/features/x.dart:9:3)',
);

int _innerBuildMarker() => throw StateError('inner-provider-failure');

int _innerDbMarker() => throw SqliteException(
  extendedResultCode: 2067,
  message: 'UNIQUE constraint failed: expenses.id',
  causingStatement: 'INSERT INTO expenses (id, comment) VALUES (?, ?)',
  parametersToStatement: ['expense-1', _comment],
);

Object _providerError(int Function() body, {bool nested = false}) {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  final inner = Provider<int>((ref) => body());
  final outer = Provider<int>((ref) => ref.watch(inner) + 1);
  try {
    container.read(nested ? outer : inner);
  } catch (e) {
    return e;
  }
  throw StateError('provider did not fail');
}

void main() {
  late Directory dir;
  late LogCapture logs;
  late File file;
  FlutterExceptionHandler? flutterOnError;
  ErrorCallback? platformOnError;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('milionchik_provider_stack');
    logs = LogCapture();
    file = File('${dir.path}/pending_reports.jsonl');
    final queue = ErrorReportQueue()
      ..context = const {'appVersion': '0.1.0+1'}
      ..attach(file);
    flutterOnError = FlutterError.onError;
    platformOnError = PlatformDispatcher.instance.onError;
    FlutterError.onError = (_) {};
    installErrorHandlers(queue);
  });

  tearDown(() async {
    FlutterError.onError = flutterOnError;
    PlatformDispatcher.instance.onError = platformOnError;
    await logs.dispose();
    dir.deleteSync(recursive: true);
  });

  Map<String, Object?> report() =>
      jsonDecode(file.readAsLinesSync().single) as Map<String, Object?>;

  test('необработанная ProviderException: в отчёте и в логе стек из '
      'провайдера, затем место повторного выброса', () {
    final error = _providerError(_innerBuildMarker);
    expect(error.runtimeType.toString(), 'ProviderException');

    PlatformDispatcher.instance.onError!(error, _outer);

    final r = report();
    expect(r['kind'], 'crash');
    expect(r['message'], 'StateError: Bad state: inner-provider-failure');
    final stack = r['stack']! as String;
    expect(stack, contains('_innerBuildMarker'));
    expect(stack, contains(_rethrown));
    expect(stack, contains('_outerRethrowSite'));
    expect(
      stack.indexOf('_innerBuildMarker'),
      lessThan(stack.indexOf('_outerRethrowSite')),
    );
    expect(logs.text, contains('_innerBuildMarker'));
    expect(logs.text, contains('_outerRethrowSite'));
    expect(
      logs.text,
      contains(
        'uncaught error: StateError: Bad state: inner-provider-failure '
        '(thrown in a provider)',
      ),
    );
  });

  test('ProviderException от провайдера, зависящего от упавшего: кадр '
      'исходного провайдера на месте', () {
    PlatformDispatcher.instance.onError!(
      _providerError(_innerBuildMarker, nested: true),
      _outer,
    );

    final stack = report()['stack']! as String;
    expect(stack, contains('_innerBuildMarker'));
    expect(stack, contains('_outerRethrowSite'));
    expect(logs.text, contains('_innerBuildMarker'));
  });

  test('ошибка базы внутри ProviderException: параметры скрыты, стек '
      'провайдера сохранён', () {
    PlatformDispatcher.instance.onError!(
      _providerError(_innerDbMarker),
      _outer,
    );

    final r = report();
    expect(r['stack'], contains('_innerDbMarker'));
    expect(r['message'], contains('<text:${_comment.length}>'));
    for (final text in [jsonEncode(r), logs.text]) {
      expect(text, isNot(contains(_comment)));
    }
    expect(logs.text, contains('_innerDbMarker'));
  });

  test('ошибка фреймворка с ProviderException: отчёт error со стеком '
      'провайдера', () {
    FlutterError.onError!(
      FlutterErrorDetails(
        exception: _providerError(_innerBuildMarker),
        stack: _outer,
        library: 'widgets library',
      ),
    );

    final r = report();
    expect(r['kind'], 'error');
    expect(r['stack'], contains('_innerBuildMarker'));
    expect(r['stack'], contains('_outerRethrowSite'));
    expect(logs.text, contains('_innerBuildMarker'));
    expect(logs.text, contains('(thrown in a provider)'));
  });

  test('обычная ошибка без провайдера: стек как есть, без пометки', () {
    PlatformDispatcher.instance.onError!(StateError('plain'), _outer);

    expect(
      report()['stack'],
      '#0      _outerRethrowSite (package:milionchik/features/x.dart:9:3)',
    );
    expect(logs.text, isNot(contains(_rethrown)));
    expect(logs.text, isNot(contains('(thrown in a provider)')));
  });
}
