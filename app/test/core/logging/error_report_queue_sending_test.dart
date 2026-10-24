import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/core/logging/error_report_sender.dart';
import 'package:milionchik/core/logging/error_reports.dart';
import 'package:milionchik/data/api/api_client.dart';
import 'package:milionchik/data/api/api_config.dart';
import 'package:milionchik/data/api/client_errors_api.dart';
import 'package:milionchik/data/api/token_store.dart';

import '../../data/api/fake_api_adapter.dart';

const AuthTokens _tokens = AuthTokens(
  accessToken: 'ACCESS-reports-hotel-india',
  refreshToken: 'REFRESH-reports-juliet-kilo',
);

final class _Env {
  _Env(this.dir, FakeHandler handler, {AuthTokens? tokens, bool? session})
    : adapter = FakeApiAdapter(handler),
      queue = ErrorReportQueue()
        ..context = const {
          'appVersion': '0.1.0+1',
          'androidSdk': 36,
          'deviceModel': 'sdk_gphone64_x86_64',
        } {
    queue.attach(file);
    client = ApiClient(
      config: ApiConfig.resolve(define: '', debugBuild: true),
      tokens: MemoryTokenStore(tokens),
      adapter: adapter,
      newRequestId: () => 'ridreports${(_rid++).toString().padLeft(6, '0')}',
    );
    sender = ErrorReportSender(
      queue: queue,
      api: ClientErrorsApi(client),
      withSession: () => session ?? tokens != null,
      appVersion: '0.1.0+1',
    );
  }

  final Directory dir;
  final FakeApiAdapter adapter;
  final ErrorReportQueue queue;
  late final ApiClient client;
  late final ErrorReportSender sender;
  int _rid = 1;

  File get file => File('${dir.path}/pending_reports.jsonl');

  List<String> get lines => file.existsSync() ? file.readAsLinesSync() : [];

  List<String> get messages => [
    for (final line in lines) (jsonDecode(line) as Map)['message'] as String,
  ];

  List<FakeCall> get posts => adapter.callsTo('/client-errors');

  void crash(String name) => queue.add(
    'crash',
    StateError('crash-$name'),
    StackTrace.fromString('#0 main (package:milionchik/main.dart:1)'),
  );
}

FakeReply _accepted(FakeCall call) =>
    FakeReply.json(202, {'id': 'srv-${call.json['message']}'});

void main() {
  late Directory dir;
  late LogCapture logs;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('milionchik_reports_send');
    logs = LogCapture();
  });
  tearDown(() async {
    await logs.dispose();
    dir.deleteSync(recursive: true);
  });

  test('очередь уходит по одному в порядке записи, после 202 строки '
      'удаляются, файл пуст; в логе сколько, результат и мс', () async {
    final env = _Env(dir, _accepted)
      ..crash('one')
      ..crash('two');
    expect(env.lines, hasLength(2));

    final result = await env.sender.send('start');

    expect(env.posts.map((c) => c.json['message']), [
      'StateError: Bad state: crash-one',
      'StateError: Bad state: crash-two',
    ]);
    final body = env.posts.first.json;
    expect(body, {
      'appVersion': '0.1.0+1',
      'androidSdk': 36,
      'deviceModel': 'sdk_gphone64_x86_64',
      'kind': 'crash',
      'message': 'StateError: Bad state: crash-one',
      'stack': '#0 main (package:milionchik/main.dart:1)',
      'logs': null,
    });
    expect(env.file.existsSync(), isFalse);
    expect(result.sent, 2);
    expect(result.left, 0);
    expect(result.failure, isNull);
    final info = logs.linesOf('errors', Level.INFO);
    expect(
      info,
      contains(
        endsWith(
          'INFO  [errors] error reports sending count=2 reason=start '
          'session=no',
        ),
      ),
    );
    expect(
      info,
      contains(
        matches(
          r'INFO  \[errors\] error reports done sent=2 dropped=0 left=0 of 2 '
          r'reason=start in \d+ms$',
        ),
      ),
    );
  });

  test('нет сети на втором отчёте: первый удалён, второй остаётся; '
      'следующий запуск по сети отправляет его', () async {
    final env =
        _Env(dir, (call) {
            if (call.json['message'] == 'StateError: Bad state: crash-b') {
              throw const SocketException('Network is unreachable');
            }
            return _accepted(call);
          })
          ..crash('a')
          ..crash('b')
          ..crash('c');

    final first = await env.sender.send('start');

    expect(env.posts, hasLength(2));
    expect(env.messages, [
      'StateError: Bad state: crash-b',
      'StateError: Bad state: crash-c',
    ]);
    expect(first.sent, 1);
    expect(first.left, 2);
    expect(
      logs.linesOf('errors', Level.WARNING),
      contains(
        matches(
          r'WARN  \[errors\] error report not sent kind=crash '
          r'rid=ridreports000002: ApiNetworkFailure connection .* after \d+ms '
          r'→ kept, retry on next start or when network appears$',
        ),
      ),
    );
    expect(
      logs.linesOf('errors', Level.INFO),
      contains(
        matches(
          r'error reports stopped sent=1 dropped=0 left=2 of 3 reason=start '
          r'in \d+ms: ApiNetworkFailure, see warning above$',
        ),
      ),
    );

    final server = <String>[];
    final env2 = _Env(dir, (call) {
      server.add(call.json['message'] as String);
      return _accepted(call);
    });
    final second = await env2.sender.send('network');

    expect(server, [
      'StateError: Bad state: crash-b',
      'StateError: Bad state: crash-c',
    ]);
    expect(second.sent, 2);
    expect(env2.file.existsSync(), isFalse);
  });

  for (final (name, reply) in [
    ('503 сервера', FakeReply.error(503, 'internal', 'сломалось')),
    (
      '429 лимита',
      FakeReply.error(429, 'too_many_attempts', 'Слишком много попыток'),
    ),
  ]) {
    test('ошибка $name: отчёт не удалён, остальные не отправлялись', () async {
      final env = _Env(dir, (_) => reply)
        ..crash('x')
        ..crash('y');

      final result = await env.sender.send('start');

      expect(env.posts, hasLength(1));
      expect(env.lines, hasLength(2));
      expect(result.sent, 0);
      expect(result.left, 2);
      expect(result.failure, isNotNull);
    });
  }

  test('400 bad_request - отчёт снят (сервер его не примет), следующий '
      'отправлен', () async {
    final env =
        _Env(dir, (call) {
            if (call.json['message'] == 'StateError: Bad state: crash-bad') {
              return FakeReply.error(400, 'bad_request', 'Неверный отчёт');
            }
            return _accepted(call);
          })
          ..crash('bad')
          ..crash('good');

    final result = await env.sender.send('start');

    expect(env.posts, hasLength(2));
    expect(result.sent, 1);
    expect(result.dropped, 1);
    expect(env.file.existsSync(), isFalse);
    expect(
      logs.linesOf('errors', Level.WARNING),
      contains(
        endsWith(
          'error report rejected kind=crash rid=ridreports000001: '
          'ApiErrorResponse 400 code=bad_request → dropped, the server will '
          'not accept it',
        ),
      ),
    );
  });

  test('битая строка снята с warn, версия без appVersion берётся текущая', () {
    final env = _Env(dir, _accepted);
    env.file.writeAsStringSync(
      'not-json-line\n'
      '${jsonEncode({'kind': 'error', 'message': 'FlutterError: early', 'stack': null})}\n',
    );

    return env.sender.send('start').then((result) {
      expect(result.dropped, 1);
      expect(result.sent, 1);
      expect(env.posts.single.json['appVersion'], '0.1.0+1');
      expect(env.posts.single.json['kind'], 'error');
      expect(
        logs.linesOf('errors', Level.WARNING),
        contains(
          contains(
            'queued error report line 1 is malformed: not JSON: '
            'Unexpected character',
          ),
        ),
      );
    });
  });

  test('отчёт, записанный во время отправки, не теряется', () async {
    final gate = Completer<void>();
    late _Env env;
    env = _Env(dir, (call) async {
      if (!gate.isCompleted) {
        env.crash('during');
        gate.complete();
      }
      return _accepted(call);
    })..crash('before');

    await env.sender.send('start');

    expect(env.posts, hasLength(1));
    expect(env.messages, ['StateError: Bad state: crash-during']);
  });

  test('два вызова сразу - одна отправка, второй ждёт её', () async {
    final env = _Env(dir, (call) async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      return _accepted(call);
    })..crash('once');

    final results = await Future.wait([
      env.sender.send('start'),
      env.sender.send('network'),
    ]);

    expect(env.posts, hasLength(1));
    expect(identical(results[0], results[1]), isTrue);
    expect(
      logs.linesOf('errors'),
      contains(
        endsWith(
          'error reports send reason=network joins the running one '
          'reason=start',
        ),
      ),
    );
  });

  test('с сессией - с токеном; сессии в хранилище нет - анонимно', () async {
    final withToken = _Env(dir, _accepted, tokens: _tokens)..crash('token');
    await withToken.sender.send('start');
    expect(
      withToken.posts.single.header('Authorization'),
      'Bearer ${_tokens.accessToken}',
    );

    final noTokens = _Env(dir, _accepted, session: true)..crash('anon');
    await noTokens.sender.send('start');
    final call = noTokens.posts.single;
    expect(call.header('Authorization'), isNull);
    expect(call.json['message'], 'StateError: Bad state: crash-anon');
    expect(
      logs.linesOf('errors'),
      contains(
        contains(
          'POST /client-errors kind=crash not sent with session: session '
          'ended: noSession',
        ),
      ),
    );
    expect(logs.text, isNot(contains(_tokens.accessToken)));
  });

  test('пустая очередь - запросов нет', () async {
    final env = _Env(dir, _accepted);

    final result = await env.sender.send('start');

    expect(result.queued, 0);
    expect(env.adapter.calls, isEmpty);
  });
}
