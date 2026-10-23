import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/data/api/api_client.dart';
import 'package:milionchik/data/api/api_config.dart';

import 'fake_api_adapter.dart';

void main() {
  late LogCapture logs;
  final config = ApiConfig.resolve(define: '', debugBuild: true);

  setUp(() => logs = LogCapture(level: Level.INFO));
  tearDown(() => logs.dispose());

  ApiClient client(FakeApiAdapter adapter, [List<String>? ids]) {
    var n = 0;
    return ApiClient(
      config: config,
      adapter: adapter,
      newRequestId: ids == null ? null : () => ids[n++],
    );
  }

  test(
    'каждый запрос несёт X-Request-Id, тот же rid в ответе и в логе',
    () async {
      final adapter = FakeApiAdapter(
        (call) => FakeReply.json(200, {
          'status': 'ok',
          'version': '0.1.0',
          'db': 'ok',
        }),
      );
      final api = client(adapter, ['rid0000000000001', 'rid0000000000002']);

      final first = await api.health();
      final second = await api.health();

      expect(adapter.calls.map((c) => c.header('X-Request-Id')), [
        'rid0000000000001',
        'rid0000000000002',
      ]);
      expect(first.requestId, 'rid0000000000001');
      expect(second.requestId, 'rid0000000000002');
      expect(first.status, 'ok');
      expect(
        adapter.calls.first.options.uri.toString(),
        'http://10.0.2.2:8080/api/v1/health',
      );

      final lines = logs.linesOf('api', Level.INFO);
      expect(
        lines.where((l) => l.contains('[api] GET /api/v1/health 200 in ')),
        hasLength(2),
      );
      expect(
        lines.any(
          (l) => RegExp(
            r'INFO  \[api\] GET /api/v1/health 200 in \d+ms size=\d+ '
            r'rid=rid0000000000001$',
          ).hasMatch(l),
        ),
        isTrue,
        reason: lines.join('\n'),
      );
    },
  );

  test('без подмены rid - 16 hex, разный у запросов', () async {
    final adapter = FakeApiAdapter((call) => const FakeReply(204));
    final api = ApiClient(config: config, adapter: adapter);

    await api.post('/auth/logout', auth: false);
    await api.post('/auth/logout', auth: false);

    final ids = adapter.calls.map((c) => c.header('X-Request-Id')).toList();
    expect(ids, everyElement(matches(RegExp(r'^[0-9a-f]{16}$'))));
    expect(ids.toSet(), hasLength(2));
  });

  test(
    'в строке лога путь без query, размер ответа в байтах, без тел на info',
    () async {
      final adapter = FakeApiAdapter(
        (call) => FakeReply.json(200, {'cursor': 'cursor-body-marker'}),
      );
      final api = client(adapter, ['ridquery00000001']);

      await api.get(
        '/sync/pull',
        query: {'cursor': 'query-value-marker', 'limit': 500},
        auth: false,
      );

      expect(adapter.calls.single.options.uri.query, contains('limit=500'));
      final line = logs.linesOf('api').where((l) => l.contains('rid=')).single;
      expect(line, contains('GET /api/v1/sync/pull 200 in '));
      expect(line, contains('size=31 '));
      expect(line, isNot(contains('query-value-marker')));
      expect(line, isNot(contains('?')));
      expect(logs.text, isNot(contains('cursor-body-marker')));
    },
  );

  test('4xx - info с кодом ошибки, 5xx - warn', () async {
    final adapter = FakeApiAdapter(
      (call) => call.path.endsWith('/budgets')
          ? FakeReply.error(409, 'conflict')
          : FakeReply.json(500, {
              'error': {'code': 'internal', 'message': 'x', 'rid': 'r'},
            }),
    );
    final api = client(adapter, ['rid4xx0000000001', 'rid5xx0000000001']);

    await expectLater(
      api.post('/budgets', body: const {}, auth: false),
      throwsA(anything),
    );
    await expectLater(api.get('/me', auth: false), throwsA(anything));

    final records = logs.records
        .where((r) => r.loggerName == 'api' && r.message.contains('rid='))
        .toList();
    expect(records[0].level, Level.INFO);
    expect(records[0].message, contains('POST /api/v1/budgets 409 in '));
    expect(records[0].message, contains('rid=rid4xx0000000001 code=conflict'));
    expect(records[1].level, Level.WARNING);
    expect(records[1].message, contains('GET /api/v1/me 500 in '));
    expect(records[1].message, contains('code=internal'));
  });
}
