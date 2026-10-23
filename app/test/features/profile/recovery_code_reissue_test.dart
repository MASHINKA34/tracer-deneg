import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/features/auth/recovery_code_screen.dart';
import 'package:milionchik/features/auth/recovery_code_state.dart';
import 'package:milionchik/features/profile/profile_screen.dart';
import 'package:milionchik/features/profile/recovery_code_reissue_screen.dart';
import 'package:milionchik/ui/components/button.dart';
import 'package:milionchik/ui/components/snackbar.dart';

import '../../data/api/fake_api_adapter.dart';
import 'profile_fixture.dart';
import 'profile_harness.dart';

const String _password = 'Pw-alpha-bravo-charlie';
const String _wrongPassword = 'Pw-zulu-yankee-xray';
const String _newCode = 'K7M2-P9QR-T4VW';
const String _field = 'Введи пароль, чтобы подтвердить';

FakeReply _server(FakeCall call) {
  if (call.method != 'POST' || !call.path.endsWith('/auth/recovery-code')) {
    throw StateError('unexpected ${call.method} ${call.path}');
  }
  if (call.json['password'] != _password) {
    return FakeReply.error(401, 'bad_credentials', 'Неверный пароль');
  }
  return FakeReply.json(200, {'recoveryCode': _newCode.replaceAll('-', '')});
}

Future<ProfileHarness> _open(
  WidgetTester tester, {
  FakeHandler server = _server,
}) async {
  final h = await ProfileHarness.start(tester, server: server);
  await h.openProfile();
  await h.tap(h.row('Код восстановления'));
  expect(find.byType(RecoveryCodeReissueScreen), findsOneWidget);
  return h;
}

Future<void> _submit(ProfileHarness h) =>
    h.tap(find.widgetWithText(AppButton, 'Перевыпустить код'));

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testWidgets('неверный пароль - ошибка под полем, экран кода не открыт, '
      'в логе код ответа и rid без пароля', (tester) async {
    final h = await _open(tester);

    await h.enter(_field, _wrongPassword);
    await _submit(h);

    expect(h.errorUnder(_field), 'Неверный пароль');
    expect(find.byType(RecoveryCodeReissueScreen), findsOneWidget);
    expect(find.byType(RecoveryCodeScreen), findsNothing);
    expect(h.container.read(pendingRecoveryCodeProvider), isNull);
    final call = h.adapter.callsTo('/auth/recovery-code').single;
    expect(call.json, {'password': _wrongPassword});
    expect(
      call.header('Authorization'),
      'Bearer ${ProfileHarness.tokens.accessToken}',
    );
    expect(
      h.linesOf('profile', Level.INFO),
      contains(
        matches(
          r'INFO  \[profile\] recovery code reissue rejected '
          r'code=bad_credentials status=401 userId=user-server-77 '
          r'rid=ridprofile000001 in \d+ms → wrong password, error under the '
          r'field, old code still works$',
        ),
      ),
    );
    expect(h.logs.text, isNot(contains(_wrongPassword)));

    await h.enter(_field, '$_wrongPassword!');
    expect(h.errorUnder(_field), isNull);
  });

  testWidgets('пустой пароль - «Введи пароль» под полем, запроса нет', (
    tester,
  ) async {
    final h = await _open(tester);

    await _submit(h);

    expect(h.errorUnder(_field), 'Введи пароль');
    expect(h.adapter.calls, isEmpty);
  });

  testWidgets('верный пароль - экран нового кода, «Продолжить» возвращает в '
      'профиль; код в лог не попадает', (tester) async {
    final h = await _open(tester);

    await h.enter(_field, _password);
    await _submit(h);

    expect(find.byType(RecoveryCodeScreen), findsOneWidget);
    expect(find.text(_newCode), findsOneWidget);
    expect(
      h.container.read(pendingRecoveryCodeProvider)?.reason,
      RecoveryCodeReason.reissue,
    );
    expect(
      h.linesOf('profile', Level.INFO),
      contains(
        matches(
          r'INFO  \[profile\] recovery code reissued userId=user-server-77 '
          r'rid=ridprofile000001 in \d+ms → code screen, the old code no '
          r'longer works$',
        ),
      ),
    );

    await h.tap(find.text('Я сохранил код в надёжном месте'));
    await h.tap(find.widgetWithText(AppButton, 'Продолжить'));

    expect(find.byType(RecoveryCodeScreen), findsNothing);
    expect(find.byType(ProfileScreen), findsOneWidget);
    expect(h.container.read(pendingRecoveryCodeProvider), isNull);
    expect(
      h.linesOf('auth'),
      contains(endsWith('reissued recovery code confirmed → back to /profile')),
    );
    expect(
      h.linesOf('api'),
      containsAll([
        allOf(contains('→ POST /api/v1/auth/recovery-code'), contains('body=')),
        allOf(
          contains('← POST /api/v1/auth/recovery-code 200'),
          contains('body='),
        ),
      ]),
    );
    for (final secret in [_password, _newCode, _newCode.replaceAll('-', '')]) {
      expect(h.logs.text, isNot(contains(secret)), reason: secret);
    }
  });

  testWidgets('нет сети - снекбар, поле без ошибки, старый код на месте', (
    tester,
  ) async {
    final h = await _open(
      tester,
      server: (call) =>
          throw const SocketException('Connection refused (test)'),
    );

    await h.enter(_field, _password);
    await _submit(h);

    expect(
      find.descendant(
        of: find.byType(AppSnackbar),
        matching: find.text(
          'Нет связи с сервером. Проверь интернет и попробуй ещё раз',
        ),
      ),
      findsOneWidget,
    );
    expect(h.errorUnder(_field), isNull);
    expect(h.container.read(pendingRecoveryCodeProvider), isNull);
    expect(
      h.linesOf('profile', Level.WARNING),
      contains(
        allOf(
          contains('recovery code reissue failed ApiNetworkFailure'),
          contains('userId=$profileUserId rid=ridprofile000001'),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
  });

  testWidgets('«назад» с экрана перевыпуска - снова профиль, запроса нет', (
    tester,
  ) async {
    final h = await _open(tester);

    await tester.tap(find.bySemanticsLabel('Назад').last);
    await h.settle();

    expect(find.byType(RecoveryCodeReissueScreen), findsNothing);
    expect(find.byType(ProfileScreen), findsOneWidget);
    expect(h.adapter.calls, isEmpty);
    expect(
      h.linesOf('nav'),
      contains(endsWith('recovery code reissue closed by back button')),
    );
  });
}
