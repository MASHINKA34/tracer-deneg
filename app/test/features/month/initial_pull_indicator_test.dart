import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/data/current_user.dart';
import 'package:milionchik/data/repositories/budgets_repository.dart';
import 'package:milionchik/data/repositories/categories_repository.dart';
import 'package:milionchik/data/repositories/expenses_repository.dart';
import 'package:milionchik/data/repositories/outbox_queue.dart';
import 'package:milionchik/data/session/session_state.dart';
import 'package:milionchik/features/auth/recovery_code_screen.dart';
import 'package:milionchik/features/month/month_header.dart';
import 'package:milionchik/features/month/month_screen.dart';
import 'package:milionchik/ui/components/button.dart';
import 'package:milionchik/ui/components/snackbar.dart';
import 'package:milionchik/ui/icons/app_icon.dart';
import 'package:shared/shared.dart';

import '../../data/api/fake_api_adapter.dart';
import '../../data/sync/pull_fixture.dart';
import '../auth/auth_harness.dart';
import '../recurring/recurring_fixture.dart' show writeWhileShown;

const _password = 'Pass-Word-Initial-Pull-Thirty-Three';

const _loading = 'Загружаем данные с сервера';

final _personal = serverPersonal();

final _presets = serverPresets(_personal.id);

FakePullServer _serverPages({List<Expense> expenses = const []}) =>
    FakePullServer([
      SyncPullResponse(
        budgets: [_personal],
        members: [ownerOf(_personal.id)],
        categories: _presets,
        cursor: 12,
        hasMore: true,
      ),
      SyncPullResponse(expenses: expenses, cursor: 20, hasMore: false),
    ]);

FakeHandler _withAuth(
  FakePullServer pull, {
  String? recoveryCode,
  FakeReply? Function(FakeCall call)? override,
}) => (call) async {
  final replaced = override?.call(call);
  if (replaced != null) return replaced;
  if (call.path.endsWith('/auth/login') ||
      call.path.endsWith('/auth/register')) {
    return signedIn(
      status: recoveryCode == null ? 200 : 201,
      id: pullUserId,
      login: 'anya_m',
      recoveryCode: recoveryCode,
    );
  }
  return pull.handle(call);
};

Finder _headerIcon(AppIcons icon) => find.descendant(
  of: find.byType(MonthHeaderView),
  matching: find.byWidgetPredicate((w) => w is AppIcon && w.icon == icon),
);

Future<void> _frames(WidgetTester tester, [int count = 10]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _signIn(AuthHarness h) async {
  await h.enter('Логин', 'anya_m');
  await h.enter('Пароль', _password);
  await h.tester.tap(find.widgetWithText(AppButton, 'Войти'));
  await _frames(h.tester);
}

void main() {
  testWidgets('вход: пока идёт первая загрузка, в шапке индикатор вместо '
      'облака; после - личный бюджет и 11 категорий с сервера', (tester) async {
    final pull = _serverPages();
    final gate = Completer<void>();
    pull.before[1] = (call) async {
      await gate.future;
      return null;
    };
    final h = await AuthHarness.start(tester, server: _withAuth(pull));

    await _signIn(h);

    expect(find.byType(MonthScreen), findsOneWidget);
    expect(pull.cursors, [0]);
    expect(find.bySemanticsLabel(_loading), findsOneWidget);
    expect(_headerIcon(AppIcons.refresh), findsOneWidget);
    expect(_headerIcon(AppIcons.cloudCheck), findsNothing);
    expect(find.text(DriftBudgetsRepository.personalName), findsNothing);

    gate.complete();
    await _frames(tester);

    expect(pull.cursors, [0, 12]);
    expect(find.bySemanticsLabel(_loading), findsNothing);
    expect(find.bySemanticsLabel('Синхронизировано'), findsOneWidget);
    expect(_headerIcon(AppIcons.cloudCheck), findsOneWidget);
    expect(find.text(DriftBudgetsRepository.personalName), findsOneWidget);
    final categories = await tester.runAsync(
      () => h.db.customSelect('SELECT id FROM categories').get(),
    );
    expect(categories, hasLength(11));
    expect(
      {for (final r in categories!) r.read<String>('id')},
      {for (final c in _presets) c.id},
    );
    expect(
      h.linesOf('sync', Level.INFO),
      containsAllInOrder([
        endsWith(
          'initial pull requested reason=login → starts when the main screen '
          'opens',
        ),
        matches(
          RegExp(
            r'pull done reason=login pages=2 entities=13 budgets=1 members=1 '
            r'profiles=0 categories=11 expenses=0 recurring=0 removed=0 '
            r'cursor=0→20 in \d+ms$',
          ),
        ),
      ]),
    );
    expect(
      h.linesOf('month', Level.FINE),
      contains(contains('header sync indicator loading → done')),
    );
  });

  testWidgets('регистрация: загрузка ждёт, пока сохранят код, и идёт на '
      'главной после «Продолжить»', (tester) async {
    final pull = _serverPages();
    final h = await AuthHarness.start(
      tester,
      server: _withAuth(pull, recoveryCode: 'WZ5N-QR8H-MV3T'),
    );
    await h.tapText('Зарегистрироваться');
    await h.enter('Как тебя зовут', 'Аня');
    await h.enter('Логин', 'anya_m');
    await h.enter('Пароль', _password);
    await h.enter('Повтори пароль', _password);
    await h.tapText('Создать аккаунт');

    expect(find.byType(RecoveryCodeScreen), findsOneWidget);
    expect(pull.cursors, isEmpty);

    await h.tapText('Я сохранил код в надёжном месте');
    await h.tapText('Продолжить');
    await _frames(tester);

    expect(find.byType(MonthScreen), findsOneWidget);
    expect(pull.cursors, [0, 12]);
    expect(find.text(DriftBudgetsRepository.personalName), findsOneWidget);
    expect(
      h.linesOf('sync', Level.INFO),
      contains(matches(RegExp(r'pull done reason=register pages=2 '))),
    );
  });

  testWidgets('ошибка загрузки: снекбар «Не удалось загрузить» с «Повторить», '
      'в шапке ошибка, данные на телефоне на месте; «Повторить» догружает', (
    tester,
  ) async {
    final pull = _serverPages(
      expenses: [
        serverExpense(
          id: 'e-new',
          budgetId: _personal.id,
          categoryId: _presets[1].id,
          kopecks: 150000,
          seq: 19,
        ),
      ],
    );
    var down = true;
    final h = await AuthHarness.start(
      tester,
      server: _withAuth(
        pull,
        override: (call) => down && call.path.endsWith('/sync/pull')
            ? FakeReply.error(503, 'internal', 'Сервер недоступен')
            : null,
      ),
    );
    await writeWhileShown(tester, () async {
      final user = SessionCurrentUser(pullUserId);
      final outbox = DriftOutboxQueue(h.db);
      await DriftBudgetsRepository(
        h.db,
        currentUser: user,
        outbox: outbox,
      ).applyFromServer([_personal]);
      await DriftCategoriesRepository(
        h.db,
        currentUser: user,
        outbox: outbox,
      ).applyFromServer(_presets);
      await DriftExpensesRepository(
        h.db,
        currentUser: user,
        outbox: outbox,
      ).applyFromServer([
        serverExpense(
          id: 'e-old',
          budgetId: _personal.id,
          categoryId: _presets.first.id,
          seq: 5,
        ),
      ]);
    });

    await _signIn(h);

    expect(h.session, isA<SessionActive>());
    expect(find.byType(AppSnackbar), findsOneWidget);
    expect(find.text('Не удалось загрузить'), findsOneWidget);
    expect(find.text('Повторить'), findsOneWidget);
    expect(find.bySemanticsLabel('Ошибка синхронизации'), findsOneWidget);
    expect(_headerIcon(AppIcons.alertCircle), findsOneWidget);
    expect(find.text(DriftBudgetsRepository.personalName), findsOneWidget);
    expect(find.text(Money(64000).format()), findsWidgets);
    expect(find.text(Money(150000).format()), findsNothing);
    expect(
      h.linesOf('sync', Level.SEVERE),
      contains(
        contains(
          'pull failed reason=login stage=request page=1 cursor=0 attempt=1 '
          'ApiServerFailure: 503 code=internal rid=ridauthscreen001',
        ),
      ),
    );
    expect(
      h.linesOf('month', Level.INFO),
      contains(
        endsWith(
          'pull failed #1 reason=login ApiServerFailure → snackbar with '
          'retry, data on the phone kept',
        ),
      ),
    );

    down = false;
    await tester.tap(find.text('Повторить'));
    await _frames(tester, 20);

    expect(find.text('Не удалось загрузить'), findsNothing);
    expect(find.bySemanticsLabel('Синхронизировано'), findsOneWidget);
    expect(find.text(Money(150000).format()), findsWidgets);
    expect(find.text(Money(64000).format()), findsWidgets);
    expect(
      h.linesOf('month', Level.INFO),
      contains(endsWith('pull retry tap on snackbar → pull reason=retry')),
    );
    expect(
      h.linesOf('sync', Level.INFO),
      contains(
        matches(RegExp(r'pull done reason=retry pages=2 .*cursor=0→20 ')),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
