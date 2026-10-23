import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:server/config/config.dart';
import 'package:server/server_app.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/test_support.dart';

void main() {
  late LogCapture logs;
  late RunningServer server;
  late HttpClient http;
  var stopped = false;

  setUp(() async {
    logs = LogCapture();
    stopped = false;
    server = await startServer(
      ServerConfig.load(
        environment: {
          'HOST': '127.0.0.1',
          'PORT': '0',
          'DATABASE_URL': await createScratchDatabase(),
          'JWT_SECRET': 'ws-running-secret-0123456789-abcdefgh',
        },
      ),
      dbConnectAttempts: 1,
    );
    http = HttpClient();
    addTearDown(() async {
      http.close(force: true);
      if (!stopped) await server.shutdown('test');
    });
  });

  Future<Map<String, Object?>> call(
    String method,
    String path, {
    Object? body,
    String? token,
    int expected = 200,
  }) async {
    final request = await http.open(
      method,
      '127.0.0.1',
      server.port,
      '/api/v1$path',
    );
    request.headers.contentType = ContentType.json;
    if (token != null) request.headers.set('authorization', 'Bearer $token');
    if (body != null) request.write(jsonEncode(body));
    final response = await request.close();
    final text = await response.transform(utf8.decoder).join();
    expect(response.statusCode, expected, reason: '$method $path → $text');
    return text.isEmpty ? {} : jsonDecode(text) as Map<String, Object?>;
  }

  Future<({String id, String token})> register(String login) async {
    final json = await call(
      'POST',
      '/auth/register',
      body: {
        'login': login,
        'displayName': 'Участник',
        'password': 'ws-pass-1',
        'deviceName': 'test',
      },
      expected: 201,
    );
    return (
      id: (json['user']! as Map<String, Object?>)['id']! as String,
      token: json['accessToken']! as String,
    );
  }

  Future<(WebSocket, List<Map<String, Object?>>, Future<void>)> connect(
    String token,
  ) async {
    final socket = await WebSocket.connect(
      'ws://127.0.0.1:${server.port}/api/v1/ws',
      headers: {'authorization': 'Bearer $token'},
    );
    final messages = <Map<String, Object?>>[];
    final closed = Completer<void>();
    socket.listen(
      (data) =>
          messages.add(jsonDecode(data as String) as Map<String, Object?>),
      onError: (Object e) => printOnFailure('boris socket error: $e'),
      onDone: closed.complete,
    );
    addTearDown(() => socket.close());
    return (socket, messages, closed.future);
  }

  test('собранный сервер: push одного участника доходит до второго как '
      'changed; остановка закрывает подключения 4503', () async {
    final anna = await register('run.anna');
    final boris = await register('run.boris');
    final budgetId = newId();
    await call(
      'POST',
      '/budgets',
      body: {'id': budgetId, 'name': 'Семья', 'emoji': '🏠'},
      token: anna.token,
      expected: 201,
    );
    final invite = await call(
      'POST',
      '/budgets/$budgetId/invites',
      token: anna.token,
      expected: 201,
    );
    await call(
      'POST',
      '/invites/join',
      body: {'code': invite['code']},
      token: boris.token,
    );
    final pulled = await call('GET', '/sync/pull?cursor=0', token: anna.token);
    final category = (pulled['categories']! as List)
        .cast<Map<String, Object?>>()
        .firstWhere((c) => c['budgetId'] == budgetId && c['isSystem'] == false);
    final (borisSocket, borisMessages, borisClosed) = await connect(
      boris.token,
    );
    await waitUntil(
      () => logs.lines.where((l) => l.contains('ws connected')).isNotEmpty,
    );

    final at = normalizeInstant(
      DateTime.now().subtract(const Duration(minutes: 1)),
    );
    final expense = Expense(
      id: newId(),
      budgetId: budgetId,
      categoryId: category['id']! as String,
      amount: Money(64000),
      spentOn: LocalDate(2026, 10, 23),
      comment: '',
      authorId: anna.id,
      createdAt: at,
      updatedAt: at,
      updatedBy: anna.id,
    );
    final pushed = await call(
      'POST',
      '/sync/push',
      body: SyncPushRequest(
        batchId: newId(),
        changes: [SyncChange.upsert(expense)],
      ).toJson(),
      token: anna.token,
    );

    await waitUntil(
      () => borisMessages.any((m) => m['type'] == 'changed'),
      timeout: const Duration(seconds: 2),
    );
    expect(borisMessages.firstWhere((m) => m['type'] == 'changed'), {
      'type': 'changed',
      'budgetIds': [budgetId],
      'cursor': pushed['cursor'],
    });

    stopped = true;
    await server.shutdown('test stop');
    await borisClosed.timeout(const Duration(seconds: 5));
    expect(borisSocket.closeCode, 4503);
    expect(borisSocket.closeReason, 'server_shutdown');
    expect(logs.text, contains('ws closing all connections=1'));
    expect(logs.text, contains('realtime ready path=/api/v1/ws'));
  });
}
