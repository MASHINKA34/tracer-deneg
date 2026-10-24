import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/core/router.dart';
import 'package:milionchik/features/budgets/budget_invite.dart';
import 'package:milionchik/features/budgets/budget_screen.dart';
import 'package:milionchik/ui/components/button.dart';
import 'package:milionchik/ui/components/dialog.dart';
import 'package:share_plus/share_plus.dart';

import '../../support/app_scope.dart';
import '../auth/session_expired_fixture.dart' show testUnmounting;
import '../profile/profile_harness.dart';
import 'budget_screen_fixture.dart';

const String _first = 'MLN-48K2';

const String _second = 'MLN-7QXW';

final class _FakeSharer implements InviteCodeSharer {
  final List<String> texts = [];
  Object? error;

  @override
  Future<ShareResult> share(String text) async {
    texts.add(text);
    final failure = error;
    if (failure != null) throw failure;
    return const ShareResult('ru.example.chat', ShareResultStatus.success);
  }
}

List<String> _invites(ProfileHarness h) => [
  for (final call in h.adapter.calls)
    if (call.path.endsWith('/invites')) call.method,
];

Future<void> _invite(ProfileHarness h) =>
    h.tap(find.widgetWithText(AppButton, 'Пригласить'));

void main() {
  late List<String> clipboard;
  late Object? clipboardError;
  late _FakeSharer sharer;

  setUpAll(() => initializeDateFormatting('ru'));

  setUp(() {
    clipboard = [];
    clipboardError = null;
    sharer = _FakeSharer();
  });

  Future<ProfileHarness> open(WidgetTester tester, BudgetServer server) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          final error = clipboardError;
          if (error != null) throw error;
          clipboard.add(
            (call.arguments as Map<Object?, Object?>)['text']! as String,
          );
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    return openBudgetScreen(
      tester,
      server,
      overrides: [inviteCodeSharerProvider.overrideWithValue(sharer)],
    );
  }

  testUnmounting('нет кода → «Пригласить» → POST invites → MLN-48K2 и «Код '
      'действует 24 часа»; «копировать» кладёт код в буфер и показывает '
      'снекбар; «поделиться» - текст из плана; код в логах только MLN-****', (
    tester,
  ) async {
    final h = await open(tester, BudgetServer(owner: true));
    expect(find.text(_first), findsNothing);
    expect(find.text('Код действует 24 часа'), findsOneWidget);

    await _invite(h);

    expect(_invites(h), ['POST']);
    expect(find.text(_first), findsOneWidget);
    expect(find.widgetWithText(AppButton, 'Пригласить'), findsNothing);
    expect(find.text('Новый код'), findsOneWidget);

    await h.tap(find.bySemanticsLabel('Скопировать код'));
    expect(clipboard, [_first]);
    expect(snackbarWith('Код скопирован'), findsOneWidget);
    await dismissSnackbar(tester);

    await h.tap(find.bySemanticsLabel('Поделиться кодом'));
    expect(sharer.texts, [
      'Присоединяйся к бюджету «Семья» в Милиончике: код MLN-48K2, действует '
          '24 часа',
    ]);

    expect(
      h.linesOf('budgets', Level.INFO),
      containsAll([
        matches(
          'budget invite ok budgetId=$familyId code=MLN-\\*\\*\\*\\* '
          'expiresAt=2026-10-20T15:40:00.000Z status=201 '
          'rid=ridprofile000001 in \\d+ms\$',
        ),
        matches(
          'budget invite copied budgetId=$familyId code=MLN-\\*\\*\\*\\* '
          'in \\d+ms\$',
        ),
        contains(
          'budget invite share result=success budgetId=$familyId '
          'code=MLN-**** target=ru.example.chat',
        ),
      ]),
    );
    expect(h.logs.text, isNot(contains('48K2')));
    expect(h.logs.text, isNot(contains('Семья')));
  });

  testUnmounting('«Новый код»: подтверждение со старым кодом, «Отмена» - '
      'запроса нет; «Сделать новый» → новый код вместо старого', (
    tester,
  ) async {
    final h = await open(tester, BudgetServer(owner: true));
    await _invite(h);
    expect(find.text(_first), findsOneWidget);

    await h.tap(find.text('Новый код'));
    expect(find.text('Сделать новый код?'), findsOneWidget);
    expect(
      find.text(
        'Код MLN-48K2 перестанет работать. Кто ещё не вошёл по нему, тому '
        'отправь новый.',
      ),
      findsOneWidget,
    );
    await h.tap(find.widgetWithText(AppButton, 'Отмена'));
    expect(find.byType(AppDialog), findsNothing);
    expect(_invites(h), ['POST']);

    await h.tap(find.text('Новый код'));
    await h.tap(find.widgetWithText(AppButton, 'Сделать новый'));

    expect(_invites(h), ['POST', 'POST']);
    expect(find.text(_second), findsOneWidget);
    expect(find.text(_first), findsNothing);
    expect(
      h.linesOf('budgets', Level.INFO),
      contains(contains('budget new invite ok budgetId=$familyId')),
    );
    expect(h.logs.text, isNot(contains('7QXW')));
  });

  testUnmounting('без сети: снекбар «Нет связи с сервером…», кода нет, '
      '«Пригласить» снова доступна', (tester) async {
    final server = BudgetServer(owner: true)..offline = true;
    final h = await open(tester, server);

    await _invite(h);

    expect(
      snackbarWith('Нет связи с сервером. Проверь интернет и попробуй ещё раз'),
      findsOneWidget,
    );
    expect(find.text(_first), findsNothing);
    expect(
      tester
          .widget<AppButton>(find.widgetWithText(AppButton, 'Пригласить'))
          .onPressed,
      isNotNull,
    );
    expect(
      h.linesOf('budgets', Level.WARNING),
      contains(
        contains(
          'budget invite failed budgetId=$familyId ApiNetworkFailure: '
          'connection',
        ),
      ),
    );
    await dismissSnackbar(tester);
  });

  testUnmounting('буфер обмена отказал с кодом в тексте ошибки: снекбар, а в '
      'логе ошибка с MLN-****', (tester) async {
    final h = await open(tester, BudgetServer(owner: true));
    await _invite(h);
    clipboardError = PlatformException(
      code: 'clipboard',
      message: 'clip rejected text MLN-48K2 (test)',
    );

    await h.tap(find.bySemanticsLabel('Скопировать код'));

    expect(
      snackbarWith('Не получилось скопировать код. Попробуй ещё раз'),
      findsOneWidget,
    );
    expect(
      h.linesOf('budgets', Level.WARNING),
      contains(
        allOf(
          contains('budget invite copy failed budgetId=$familyId'),
          contains('clip rejected text MLN-****'),
        ),
      ),
    );
    expect(h.logs.text, isNot(contains('48K2')));
    await dismissSnackbar(tester);
  });

  testUnmounting('истёкший код не показывается - на его месте «Пригласить»', (
    tester,
  ) async {
    final h = await open(tester, BudgetServer(owner: true));
    h.container
        .read(budgetInvitesProvider.notifier)
        .remember(
          familyId,
          BudgetInvite(
            code: _first,
            expiresAt: testNow.toUtc().subtract(const Duration(minutes: 1)),
          ),
        );
    await h.settle();

    expect(find.text(_first), findsNothing);
    expect(find.widgetWithText(AppButton, 'Пригласить'), findsOneWidget);
  });

  testUnmounting('открыт сразу после создания бюджета: код создаётся сам, '
      'один раз', (tester) async {
    final h = await open(tester, BudgetServer(owner: true));
    await h.tap(find.bySemanticsLabel('Назад'));
    expect(find.byType(BudgetScreen), findsNothing);

    GoRouter.of(tester.element(find.text('Профиль').last))
        .push(AppRoutes.budgetOf(familyId), extra: BudgetScreenOpen.created);
    await h.settle();

    expect(find.byType(BudgetScreen), findsOneWidget);
    expect(find.text(_first), findsOneWidget);
    expect(_invites(h), ['POST']);
    expect(
      h.linesOf('budgets'),
      contains(
        endsWith(
          'budget screen budgetId=$familyId invite by budget created → new '
          'code',
        ),
      ),
    );
  });
}
