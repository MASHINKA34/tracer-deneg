import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/features/budgets/budget_switcher_sheet.dart';
import 'package:milionchik/features/budgets/join_budget_screen.dart';
import 'package:milionchik/ui/components/button.dart';
import 'package:milionchik/ui/components/snackbar.dart';

import '../../data/api/fake_api_adapter.dart';
import '../auth/session_expired_fixture.dart' show testUnmounting;
import '../profile/profile_harness.dart';

const String _field = 'Код';

const String _code = 'MLN-7QXW';

const String _hint =
    'После входа бюджет появится в переключателе бюджетов, а все его траты '
    'загрузятся на этот телефон.';

final class _Server {
  _Server(this.reply);

  FakeReply reply;

  FakeReply handle(FakeCall call) {
    if (call.method == 'POST' && call.path.endsWith('/invites/join')) {
      return reply;
    }
    throw StateError('unexpected ${call.method} ${call.path}');
  }
}

FakeReply _tooMany({String? retryAfter}) => FakeReply.json(
  429,
  {
    'error': {
      'code': 'too_many_attempts',
      'message': 'Слишком много неудачных попыток. Попробуй через 15 мин',
    },
  },
  {
    if (retryAfter != null) 'retry-after': [retryAfter],
  },
);

Future<ProfileHarness> _open(WidgetTester tester, _Server server) async {
  final h = await ProfileHarness.start(tester, server: server.handle);
  await tester.tap(find.bySemanticsLabel('Личный бюджет, выбрать бюджет'));
  await tester.pumpAndSettle();
  expect(find.byType(BudgetSheet), findsOneWidget);
  await h.tap(find.text('Войти по коду приглашения'));
  expect(find.byType(JoinBudgetScreen), findsOneWidget);
  return h;
}

Future<void> _join(ProfileHarness h) =>
    h.tap(find.widgetWithText(AppButton, 'Присоединиться'));

String _shown(ProfileHarness h) =>
    h.tester.widget<TextField>(h.input(_field)).controller!.text;

Finder _snackbar(String text) =>
    find.descendant(of: find.byType(AppSnackbar), matching: find.text(text));

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  test('ожидание из Retry-After округляется вверх до минут, минимум 1', () {
    expect(joinRetryMinutes(const Duration(seconds: 900)), 15);
    expect(joinRetryMinutes(const Duration(seconds: 841)), 15);
    expect(joinRetryMinutes(const Duration(seconds: 840)), 14);
    expect(joinRetryMinutes(const Duration(seconds: 60)), 1);
    expect(joinRetryMinutes(const Duration(seconds: 5)), 1);
    expect(joinRetryMinutes(Duration.zero), 1);
  });

  testUnmounting('429 с Retry-After: снекбар с временем ожидания, код в поле '
      'остаётся, ошибки под полем нет; в логе retryAfter и MLN-****', (
    tester,
  ) async {
    final server = _Server(_tooMany(retryAfter: '840'));
    final h = await _open(tester, server);

    await h.enter(_field, _code);
    await _join(h);

    expect(
      _snackbar('Слишком много попыток. Попробуй через 14 минут'),
      findsOneWidget,
    );
    expect(find.byType(JoinBudgetScreen), findsOneWidget);
    expect(_shown(h), _code);
    expect(h.errorUnder(_field), isNull);
    expect(find.text(_hint), findsOneWidget);
    expect(
      h.linesOf('budgets', Level.WARNING),
      contains(
        matches(
          'budget join rejected code=MLN-\\*\\*\\*\\* '
          'reason=too_many_attempts status=429 retryAfter=840s '
          'rid=ridprofile000001 in \\d+ms → snackbar with the wait, code '
          'kept, not joined\$',
        ),
      ),
    );
    expect(h.logs.text, isNot(contains('7QXW')));

    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    server.reply = _tooMany(retryAfter: '61');
    await _join(h);
    expect(
      _snackbar('Слишком много попыток. Попробуй через 2 минуты'),
      findsOneWidget,
    );
    expect(_shown(h), _code);
  });

  testUnmounting('429 с Retry-After 60 → «через 1 минуту»', (tester) async {
    final h = await _open(tester, _Server(_tooMany(retryAfter: '60')));

    await h.enter(_field, _code);
    await _join(h);

    expect(
      _snackbar('Слишком много попыток. Попробуй через 1 минуту'),
      findsOneWidget,
    );
    expect(_shown(h), _code);
  });

  testUnmounting('429 без Retry-After → общий текст «Попробуй позже», код в '
      'поле остаётся', (tester) async {
    final h = await _open(tester, _Server(_tooMany()));

    await h.enter(_field, _code);
    await _join(h);

    expect(_snackbar('Слишком много попыток. Попробуй позже'), findsOneWidget);
    expect(_shown(h), _code);
    expect(
      h.linesOf('budgets', Level.WARNING),
      contains(contains('retryAfter=none')),
    );
  });
}
