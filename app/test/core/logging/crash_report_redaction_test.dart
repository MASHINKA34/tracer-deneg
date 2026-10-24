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

const String _comment = 'kommentariy-romeo-sierra-tango';

const int _kopecks = 9876543210;

SqliteException _sqlError() => SqliteException(
  extendedResultCode: 2067,
  message: 'UNIQUE constraint failed: expenses.id',
  causingStatement:
      'INSERT INTO expenses (id, amount, comment) VALUES (?, ?, ?)',
  parametersToStatement: ['expense-1', _kopecks, _comment],
);

Object _providerError() {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  final failing = Provider<int>((ref) => throw _sqlError());
  try {
    container.read(failing);
  } catch (e) {
    return e;
  }
  throw StateError('provider did not fail');
}

void main() {
  late Directory dir;
  late LogCapture logs;
  late ErrorReportQueue queue;
  late File file;
  FlutterExceptionHandler? flutterOnError;
  ErrorCallback? platformOnError;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('milionchik_crash_redact');
    logs = LogCapture();
    file = File('${dir.path}/pending_reports.jsonl');
    queue = ErrorReportQueue()
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

  List<Map<String, Object?>> queued() => [
    for (final line in file.readAsLinesSync())
      jsonDecode(line) as Map<String, Object?>,
  ];

  for (final (name, error) in [
    ('ошибка базы', _sqlError),
    ('ошибка базы внутри ProviderException', _providerError),
  ]) {
    test('необработанная $name: в отчёте и в логе нет комментария и суммы '
        'из параметров запроса, тип и текст ошибки на месте', () {
      final handled = PlatformDispatcher.instance.onError!(
        error(),
        StackTrace.fromString('#0 save (package:milionchik/a.dart:1)'),
      );

      expect(handled, isTrue);
      final report = queued().single;
      expect(report['kind'], 'crash');
      final message = report['message']! as String;
      expect(message, contains('SqliteException(2067)'));
      expect(message, contains('UNIQUE constraint failed: expenses.id'));
      expect(message, contains('<text:${_comment.length}>'));
      for (final text in [jsonEncode(report), logs.text]) {
        expect(text, isNot(contains(_comment)));
        expect(text, isNot(contains('$_kopecks')));
      }
      expect(
        logs.text,
        contains('uncaught error: SqliteException: SqliteException(2067)'),
      );
    });
  }

  test('ошибка фреймворка с параметрами запроса: отчёт error без '
      'комментария', () {
    FlutterError.onError!(
      FlutterErrorDetails(
        exception: _sqlError(),
        stack: StackTrace.fromString('#0 build (package:milionchik/b.dart:2)'),
        library: 'widgets library',
      ),
    );

    final report = queued().single;
    expect(report['kind'], 'error');
    expect(report['stack'], '#0 build (package:milionchik/b.dart:2)');
    for (final text in [jsonEncode(report), logs.text]) {
      expect(text, isNot(contains(_comment)));
      expect(text, isNot(contains('$_kopecks')));
    }
    expect(
      logs.text,
      contains(
        'Flutter error in widgets library: SqliteException: '
        'SqliteException(2067)',
      ),
    );
  });
}
