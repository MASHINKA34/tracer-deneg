import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/core/logging/app_logging.dart';
import 'package:milionchik/core/logging/device_info.dart';
import 'package:milionchik/core/logging/error_reporting.dart';
import 'package:milionchik/core/logging/error_reports.dart';
import 'package:milionchik/data/current_user.dart';
import 'package:milionchik/data/db/app_database.dart';
import 'package:milionchik/data/repositories/expenses_repository.dart';
import 'package:milionchik/data/repositories/outbox_queue.dart';
import 'package:milionchik/features/profile/profile_screen.dart';
import 'package:milionchik/ui/components/button.dart';
import 'package:milionchik/ui/components/snackbar.dart';
import 'package:shared/shared.dart';

import '../../data/api/fake_api_adapter.dart';
import '../../support/app_scope.dart';
import '../auth/session_expired_fixture.dart' show testUnmounting;
import 'profile_fixture.dart';
import 'profile_harness.dart';

const String _password = 'Pw-logs-echo-foxtrot';
const String _newCode = 'H3JD-8KQZ-W2XN';
const String _comment = 'kommentariy-logs-golf-hotel';
const int _rubles = 98765;
const String _row = 'Отправить логи разработчику';

const String _leakedJwt =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.'
    'eyJzdWIiOiJ1c2VyLXNlcnZlci03NyJ9.'
    'c2lnbmF0dXJlLWxlYWtlZC1pbnRvLXRoZS1sb2c';

const ReportDevice _device = ReportDevice(
  appVersion: '0.1.0+1',
  device: DeviceInfo(
    sdkInt: 36,
    release: '16',
    model: 'sdk_gphone64_x86_64',
    manufacturer: 'Google',
  ),
  buildMode: 'debug',
  logLevel: 'debug',
);

final class _Logs {
  _Logs(this.dir)
    : logging = AppLogging.start(levelValue: 'debug', openLogcat: false) {
    logging.attachFile(Directory('${dir.path}/logs'));
  }

  final Directory dir;
  final AppLogging logging;

  ErrorReporting get reporting => ErrorReporting(
    queue: ErrorReportQueue(),
    device: _device,
    logFiles: () => [?logging.previousLogFile, ?logging.logFile],
  );
}

FakeReply _server(FakeCall call) {
  if (call.path.endsWith('/auth/recovery-code')) {
    if (call.json['password'] != _password) {
      return FakeReply.error(401, 'bad_credentials', 'Неверный пароль');
    }
    return FakeReply.json(200, {'recoveryCode': _newCode.replaceAll('-', '')});
  }
  if (call.path.endsWith('/client-errors')) {
    return FakeReply.json(202, {'id': 'srv-user-report-1'});
  }
  throw StateError('unexpected ${call.method} ${call.path}');
}

Future<ProfileHarness> _start(
  WidgetTester tester,
  _Logs logs, {
  FakeHandler server = _server,
}) async {
  final h = await ProfileHarness.start(
    tester,
    server: server,
    overrides: [errorReportingProvider.overrideWithValue(logs.reporting)],
  );
  await h.openProfile();
  return h;
}

Future<void> _addExpense(AppDatabase db) =>
    DriftExpensesRepository(
      db,
      currentUser: const SessionCurrentUser(profileUserId),
      outbox: DriftOutboxQueue(db, now: () => testNow),
      now: () => testNow,
    ).create(
      budgetId: profilePersonalId,
      categoryId: 'cat-personal-0',
      amount: Money.rubles(_rubles),
      spentOn: LocalDate(2026, 10, 19),
      comment: _comment,
    );

Finder _snackbar(String text) =>
    find.descendant(of: find.byType(AppSnackbar), matching: find.text(text));

Future<void> _closeSnackbar(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 6));
  await tester.pumpAndSettle();
}

void main() {
  late Directory dir;
  late _Logs logs;

  setUpAll(() => initializeDateFormatting('ru'));
  setUp(() {
    dir = Directory.systemTemp.createTempSync('milionchik_send_logs');
    logs = _Logs(dir);
  });
  tearDown(() async {
    await logs.logging.dispose();
    dir.deleteSync(recursive: true);
  });

  testUnmounting('«Отправить логи»: user_report с хвостом лога и устройством, '
      'снекбар «Логи отправлены»; в отчёте нет пароля, кода, токенов, '
      'суммы, комментария, логина и названий', (tester) async {
    final h = await _start(tester, logs);
    await tester.runAsync(() => _addExpense(h.db));
    await h.tap(h.row('Код восстановления'));
    await h.enter('Введи пароль, чтобы подтвердить', _password);
    await h.tap(find.widgetWithText(AppButton, 'Перевыпустить код'));
    expect(find.text(_newCode), findsOneWidget);
    await h.tap(find.text('Я сохранил код в надёжном месте'));
    await h.tap(find.widgetWithText(AppButton, 'Продолжить'));
    expect(find.byType(ProfileScreen), findsOneWidget);
    final fileText = await tester.runAsync(
      () => logs.logging.logFile!.readAsString(),
    );
    expect(fileText, contains('amount=${_rubles * 100}'));

    await h.tap(h.row(_row));

    expect(_snackbar('Логи отправлены'), findsOneWidget);
    final call = h.adapter.callsTo('/client-errors').single;
    expect(call.method, 'POST');
    expect(
      call.header('Authorization'),
      'Bearer ${ProfileHarness.tokens.accessToken}',
    );
    final body = call.json;
    expect(body['kind'], 'user_report');
    expect(body['appVersion'], '0.1.0+1');
    expect(body['androidSdk'], 36);
    expect(body['deviceModel'], 'sdk_gphone64_x86_64');
    expect(body['stack'], isNull);
    final report = body['logs']! as String;
    expect(
      body['message'],
      'user report from profile: manufacturer=Google '
      'model=sdk_gphone64_x86_64 android=16 sdk=36 app=0.1.0+1 build=debug '
      'log=debug logsBytes=${utf8.encode(report).length} files=1',
    );
    expect(report, contains('[profile] recovery code reissued'));
    expect(report, contains('INFO  [api] POST /api/v1/auth/recovery-code 200'));
    expect(report, isNot(contains('DEBUG')));
    for (final secret in [
      _password,
      _newCode,
      _newCode.replaceAll('-', ''),
      ProfileHarness.tokens.accessToken,
      ProfileHarness.tokens.refreshToken,
      '${_rubles * 100}',
      _comment,
      profileUser.login,
      'Семья',
      'Личный бюджет',
    ]) {
      expect(call.body, isNot(contains(secret)), reason: secret);
    }
    expect(
      h.linesOf('errors', Level.INFO),
      containsAllInOrder([
        matches(
          r'INFO  \[errors\] user report sending logsBytes=\d+ of \d+ '
          r'limit=204800 files=1 debugSkipped=[1-9]\d* truncated=false '
          r'masked=0 session=yes$',
        ),
        matches(
          r'INFO  \[errors\] user report sent id=srv-user-report-1 '
          r'logsBytes=\d+ rid=ridprofile000001 in \d+ms$',
        ),
      ]),
    );
    await _closeSnackbar(tester);
  });

  testUnmounting('секрет, попавший в файл лога, не уходит на сервер: '
      'маскируется точечно, в логе warn', (tester) async {
    final h = await _start(tester, logs);
    Logger('api').info('deep link token=$_leakedJwt opened');

    await h.tap(h.row(_row));

    final report = h.adapter.callsTo('/client-errors').single.json['logs']!;
    expect(report, isNot(contains(_leakedJwt)));
    expect(
      report,
      contains('deep link token=***(${_leakedJwt.length}) opened'),
    );
    expect(
      h.linesOf('errors', Level.WARNING),
      contains(
        endsWith(
          'user report logs: secret-like text found (jwt=1) → masked in the '
          'report only, log file unchanged',
        ),
      ),
    );
    await _closeSnackbar(tester);
  });

  testUnmounting('лог больше лимита - уходит хвост до maxClientErrorLogsBytes '
      'с последней строкой', (tester) async {
    final h = await _start(tester, logs);
    for (var i = 0; i < 4000; i++) {
      Logger('sync').info('filler line number=$i of the long log');
    }
    Logger('sync').info('the newest line before sending');

    await h.tap(h.row(_row));

    final report =
        h.adapter.callsTo('/client-errors').single.json['logs']! as String;
    expect(
      utf8.encode(report).length,
      lessThanOrEqualTo(maxClientErrorLogsBytes),
    );
    expect(
      utf8.encode(report).length,
      greaterThan(maxClientErrorLogsBytes - 300),
    );
    expect(report, contains('the newest line before sending'));
    expect(report, isNot(contains('filler line number=0 ')));
    expect(
      h.linesOf('errors', Level.INFO),
      contains(contains('truncated=true')),
    );
    await _closeSnackbar(tester);
  });

  testUnmounting(
    'нет сети - снекбар ошибки, в логе warn с видом отчёта и rid',
    (tester) async {
      final h = await _start(
        tester,
        logs,
        server: (call) => throw const SocketException('Network is unreachable'),
      );

      await h.tap(h.row(_row));

      expect(
        _snackbar('Нет связи с сервером. Проверь интернет и попробуй ещё раз'),
        findsOneWidget,
      );
      expect(_snackbar('Логи отправлены'), findsNothing);
      expect(
        h.linesOf('errors', Level.WARNING),
        contains(
          allOf(
            matches(
              RegExp(
                r'WARN  \[errors\] user report not sent kind=user_report '
                r'logsBytes=\d+ rid=ridprofile000001: ApiNetworkFailure '
                r'connection .* after \d+ms → error snackbar$',
                multiLine: true,
              ),
            ),
            contains('\n  stack:\n'),
          ),
        ),
      );
      await _closeSnackbar(tester);
    },
  );

  testUnmounting('два быстрых нажатия - один отчёт', (tester) async {
    final gate = Completer<void>();
    final h = await _start(
      tester,
      logs,
      server: (call) async {
        await gate.future;
        return _server(call);
      },
    );

    await tester.ensureVisible(h.row(_row));
    await tester.pumpAndSettle();
    await tester.tap(h.row(_row));
    await tester.pump();
    await tester.tap(h.row(_row));
    await tester.pump();
    gate.complete();
    await h.settle();

    expect(h.adapter.callsTo('/client-errors'), hasLength(1));
    expect(
      h.linesOf('profile'),
      contains(endsWith('profile send logs tap ignored: logs are being sent')),
    );
    await _closeSnackbar(tester);
  });
}
