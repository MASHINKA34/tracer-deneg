import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:logging/logging.dart';
import 'package:shared/logging.dart';

final class FakeCall {
  FakeCall(this.options, this.body);

  final RequestOptions options;
  final String? body;

  String get method => options.method;
  String get path => options.uri.path;
  String? header(String name) {
    final value = options.headers[name];
    return value?.toString();
  }

  Map<String, Object?> get json => jsonDecode(body!) as Map<String, Object?>;
}

final class FakeReply {
  const FakeReply(this.status, [this.body = '', this.headers = const {}]);

  FakeReply.json(this.status, Object? json, [this.headers = const {}])
    : body = jsonEncode(json);

  FakeReply.error(int status, String code, [String message = 'ошибка'])
    : this.json(status, {
        'error': {'code': code, 'message': message},
      });

  final int status;
  final String body;
  final Map<String, List<String>> headers;
}

typedef FakeHandler = FutureOr<FakeReply> Function(FakeCall call);

class FakeApiAdapter implements HttpClientAdapter {
  FakeApiAdapter(this.handler);

  final FakeHandler handler;
  final List<FakeCall> calls = [];

  List<FakeCall> callsTo(String path) => [
    for (final call in calls)
      if (call.path.endsWith(path)) call,
  ];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    String? body;
    if (requestStream != null) {
      final bytes = await requestStream.expand((chunk) => chunk).toList();
      body = utf8.decode(bytes);
    }
    final call = FakeCall(options, body);
    calls.add(call);
    final reply = await handler(call);
    return ResponseBody.fromString(
      reply.body,
      reply.status,
      headers: {
        Headers.contentTypeHeader: ['application/json; charset=utf-8'],
        ...reply.headers,
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

final class LogCapture {
  LogCapture({Level level = Level.ALL}) {
    _previous = Logger.root.level;
    Logger.root.level = level;
    _subscription = Logger.root.onRecord.listen(records.add);
  }

  final List<LogRecord> records = [];
  late final Level _previous;
  late final StreamSubscription<LogRecord> _subscription;

  List<String> get lines => [for (final r in records) formatLogRecord(r)];

  List<String> linesOf(String logger, [Level from = Level.ALL]) => [
    for (final r in records)
      if (r.loggerName == logger && r.level >= from) formatLogRecord(r),
  ];

  String get text => lines.join('\n');

  Future<void> dispose() async {
    await _subscription.cancel();
    Logger.root.level = _previous;
  }
}
