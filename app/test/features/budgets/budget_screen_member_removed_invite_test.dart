import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/features/budgets/budget_screen.dart';
import 'package:milionchik/ui/components/button.dart';
import 'package:milionchik/ui/components/dialog.dart';
import 'package:milionchik/ui/components/sheet.dart';

import '../../data/api/fake_api_adapter.dart';
import '../auth/session_expired_fixture.dart' show testUnmounting;
import '../profile/profile_harness.dart';
import 'budget_screen_fixture.dart';

const String _first = 'MLN-48K2';

const String _second = 'MLN-7QXW';

const String _revoked = 'Старый код больше не работает';

Finder _button(String label) => find.widgetWithText(AppButton, label);

List<String> _invites(ProfileHarness h) => [
  for (final call in h.adapter.calls)
    if (call.path.endsWith('/invites')) call.method,
];

Future<void> _removeDima(ProfileHarness h) async {
  await h.tester.ensureVisible(find.text('Дима'));
  await h.settle();
  await longPressAndSettle(h, find.text('Дима'));
  await h.tap(
    find.descendant(
      of: find.byType(AppSheet),
      matching: find.text('Исключить'),
    ),
  );
  await h.tap(_button('Исключить'));
}

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testUnmounting('создатель с показанным кодом исключает участника → код '
      'убран, «Старый код больше не работает» и кнопка «Новый код»; «Новый '
      'код» без подтверждения выпускает новый код', (tester) async {
    final server = BudgetServer(owner: true);
    final h = await openBudgetScreen(tester, server);
    await h.tap(_button('Пригласить'));
    expect(find.text(_first), findsOneWidget);

    await _removeDima(h);

    expect(server.removedMembers, [dimaId]);
    expect(snackbarWith('Дима больше не в бюджете'), findsOneWidget);
    expect(find.text(_first), findsNothing);
    expect(find.text(_revoked), findsOneWidget);
    expect(_button('Новый код'), findsOneWidget);
    expect(_button('Пригласить'), findsNothing);
    expect(find.bySemanticsLabel('Скопировать код'), findsNothing);
    expect(
      h.linesOf('budgets', Level.INFO),
      contains(
        matches(
          'budget remove member budgetId=$familyId: invite '
          'BudgetInvite\\(code=MLN-\\*\\*\\*\\* '
          'expiresAt=2026-10-20T15:40:00.000Z\\) revoked by the server with '
          'the removal, forgotten on this phone → «new code» offered\$',
        ),
      ),
    );
    await dismissSnackbar(tester);

    await h.tap(_button('Новый код'));

    expect(find.byType(AppDialog), findsNothing);
    expect(_invites(h), ['POST', 'POST']);
    expect(find.text(_second), findsOneWidget);
    expect(find.text(_revoked), findsNothing);
    expect(_button('Новый код'), findsNothing);
    expect(find.text('Новый код'), findsOneWidget);
    expect(h.logs.text, isNot(contains('48K2')));
    expect(h.logs.text, isNot(contains('7QXW')));
  });

  testUnmounting('кода на экране нет → после исключения по-прежнему '
      '«Пригласить», строки про старый код нет', (tester) async {
    final server = BudgetServer(owner: true);
    final h = await openBudgetScreen(tester, server);

    await _removeDima(h);

    expect(server.removedMembers, [dimaId]);
    expect(find.text(_revoked), findsNothing);
    expect(_button('Пригласить'), findsOneWidget);
    expect(_button('Новый код'), findsNothing);
    expect(_invites(h), isEmpty);
    await dismissSnackbar(tester);
  });

  testUnmounting('исключение не прошло → показанный код остаётся', (
    tester,
  ) async {
    final server = BudgetServer(owner: true);
    final h = await openBudgetScreen(tester, server);
    await h.tap(_button('Пригласить'));
    server.reject = FakeReply.error(500, 'internal_error', 'Ошибка сервера');

    await _removeDima(h);

    expect(server.removedMembers, isEmpty);
    expect(find.byType(BudgetScreen), findsOneWidget);
    expect(find.text(_first), findsOneWidget);
    expect(find.text(_revoked), findsNothing);
    await dismissSnackbar(tester);
  });
}
