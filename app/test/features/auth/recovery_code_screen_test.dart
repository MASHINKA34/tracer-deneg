import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/data/api/token_store.dart';
import 'package:milionchik/data/session/session.dart';
import 'package:milionchik/features/auth/recovery_code_screen.dart';
import 'package:milionchik/features/auth/recovery_code_state.dart';
import 'package:milionchik/features/month/month_screen.dart';
import 'package:milionchik/ui/components/bottom_nav.dart';
import 'package:milionchik/ui/components/button.dart';
import 'package:milionchik/ui/components/dialog.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/api/fake_api_adapter.dart';
import 'auth_harness.dart';

const _shown = 'K7QM-4XPA-9TRB';
const _compact = 'K7QM4XPA9TRB';
const _saved = 'Я сохранил код в надёжном месте';

const _session = Session(
  user: SessionUser(
    userId: 'user-server-77',
    login: 'anya_m',
    displayName: 'Аня',
  ),
  tokens: AuthTokens(
    accessToken: 'ACCESS-code-screen-echo-foxtrot',
    refreshToken: 'REFRESH-code-screen-golf-hotel',
  ),
);

FakeReply _noServer(FakeCall call) =>
    throw StateError('no request expected, got ${call.method} ${call.path}');

final class _FakeSharer implements RecoveryCodeSharer {
  final List<String> texts = [];
  Object? error;

  @override
  Future<ShareResult> share(String text) async {
    texts.add(text);
    final failure = error;
    if (failure != null) throw failure;
    return const ShareResult('ru.example.notes', ShareResultStatus.success);
  }
}

void main() {
  late List<String> clipboard;
  late Object? clipboardError;

  setUp(() {
    clipboard = [];
    clipboardError = null;
  });

  Future<AuthHarness> openCode(
    WidgetTester tester, {
    _FakeSharer? sharer,
    String code = 'k7qm 4xpa-9trb',
  }) async {
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
    final h = await AuthHarness.start(
      tester,
      server: _noServer,
      session: _session,
      overrides: [
        recoveryCodeSharerProvider.overrideWithValue(sharer ?? _FakeSharer()),
      ],
    );
    h.container
        .read(pendingRecoveryCodeProvider.notifier)
        .show(code, RecoveryCodeReason.register);
    await tester.pumpAndSettle();
    expect(find.byType(RecoveryCodeScreen), findsOneWidget);
    return h;
  }

  AppButton continueButton(WidgetTester tester) =>
      tester.widget<AppButton>(find.widgetWithText(AppButton, 'Продолжить'));

  void expectNoCodeInLogs(AuthHarness h) {
    for (final secret in [_shown, _compact, 'k7qm', 'K7QM']) {
      expect(h.logs.text, isNot(contains(secret)), reason: secret);
    }
  }

  testWidgets('код из ответа показан группами XXXX-XXXX-XXXX без меню; '
      '«Продолжить» неактивна, пока не отмечен чекбокс', (tester) async {
    final h = await openCode(tester);

    expect(find.text(_shown), findsOneWidget);
    expect(find.byType(AppBottomNav), findsNothing);
    expect(continueButton(tester).onPressed, isNull);

    await h.tapText('Продолжить');
    expect(find.byType(RecoveryCodeScreen), findsOneWidget);

    await h.tapText(_saved);
    expect(continueButton(tester).onPressed, isNotNull);

    await h.tapText(_saved);
    expect(continueButton(tester).onPressed, isNull);

    expect(
      h.linesOf('auth', Level.FINE),
      containsAllInOrder([
        endsWith(
          'recovery code screen shown reason=register (code is never '
          'logged)',
        ),
        endsWith('recovery code "saved" checkbox → checked: continue enabled'),
        endsWith(
          'recovery code "saved" checkbox → unchecked: continue disabled',
        ),
      ]),
    );
    expectNoCodeInLogs(h);
  });

  testWidgets('чекбокс + «Продолжить»: код стёрт из памяти, главная с меню', (
    tester,
  ) async {
    final h = await openCode(tester);

    await h.tapText(_saved);
    await h.tapText('Продолжить');

    expect(find.byType(MonthScreen), findsOneWidget);
    expect(find.byType(AppBottomNav), findsOneWidget);
    expect(find.byType(RecoveryCodeScreen), findsNothing);
    expect(h.container.read(pendingRecoveryCodeProvider), isNull);
    expect(
      h.linesOf('auth', Level.INFO),
      containsAllInOrder([
        endsWith(
          'recovery code screen closed by continue button '
          'reason=register',
        ),
        endsWith(
          'recovery code confirmed as saved reason=register → dropped from '
          'memory',
        ),
      ]),
    );
    expectNoCodeInLogs(h);
  });

  testWidgets('«Скопировать» кладёт код в буфер только по нажатию, снекбар '
      '«Код скопирован», в логе (debug) без кода', (tester) async {
    final h = await openCode(tester);
    expect(clipboard, isEmpty);

    await h.tapText('Скопировать');

    expect(clipboard, [_shown]);
    expect(find.text('Код скопирован'), findsOneWidget);
    expect(
      h.linesOf('auth', Level.FINE),
      contains(
        matches(
          RegExp(
            r'DEBUG \[auth\] recovery code copied to the clipboard by user '
            r'tap reason=register in \d+ms$',
          ),
        ),
      ),
    );
    expectNoCodeInLogs(h);
  });

  testWidgets('буфер обмена отказал с кодом в тексте ошибки: снекбар, в логе '
      'ошибка без кода', (tester) async {
    clipboardError = PlatformException(
      code: 'clipboard_failed',
      message: 'cannot store "$_shown" ($_compact)',
    );
    final h = await openCode(tester);

    await h.tapText('Скопировать');

    expect(
      find.text('Не получилось скопировать код. Попробуй ещё раз'),
      findsOneWidget,
    );
    final warning = h.linesOf('auth', Level.WARNING).single;
    expect(warning, contains('recovery code copy failed reason=register'));
    expect(warning, contains('PlatformException'));
    expect(warning, contains('clipboard_failed'));
    expect(warning, contains('****-****-****'));
    expectNoCodeInLogs(h);
  });

  testWidgets('«Поделиться» отдаёт в системное окно текст с кодом; ошибка - '
      'снекбар, в логе без кода', (tester) async {
    final sharer = _FakeSharer();
    final h = await openCode(tester, sharer: sharer);

    await h.tapText('Поделиться');

    expect(sharer.texts, ['Код восстановления Милиончика: $_shown']);
    expect(
      h.linesOf('auth', Level.FINE),
      contains(
        contains(
          'recovery code share result=success target=ru.example.notes '
          'reason=register',
        ),
      ),
    );

    sharer.error = StateError('share sheet rejected text with $_shown');
    await h.tapText('Поделиться');

    expect(
      find.text('Не получилось открыть «Поделиться». Попробуй ещё раз'),
      findsOneWidget,
    );
    expect(
      h.linesOf('auth', Level.WARNING).single,
      contains('recovery code share failed reason=register'),
    );
    expectNoCodeInLogs(h);
  });

  testWidgets('«назад» без чекбокса не уводит: диалог-подсказка; с чекбоксом '
      '«назад» ведёт на главную', (tester) async {
    final h = await openCode(tester);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byType(AppDialog), findsOneWidget);
    expect(find.text('Сначала сохрани код'), findsOneWidget);
    expect(find.byType(RecoveryCodeScreen), findsOneWidget);

    await h.tapText('Понятно');
    expect(find.byType(AppDialog), findsNothing);
    expect(find.byType(RecoveryCodeScreen), findsOneWidget);
    expect(h.container.read(pendingRecoveryCodeProvider), isNotNull);

    await h.tapText(_saved);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byType(MonthScreen), findsOneWidget);
    expect(h.container.read(pendingRecoveryCodeProvider), isNull);
    expect(
      h.linesOf('auth', Level.FINE),
      containsAllInOrder([
        endsWith(
          'back on recovery code screen before "saved" is checked → staying, '
          'reminder dialog shown reason=register',
        ),
        endsWith('recovery code screen closed by back gesture reason=register'),
      ]),
    );
  });

  testWidgets('TalkBack: код читается по символам, строка чекбокса - один '
      'элемент с отметкой, области нажатия не меньше 48 dp', (tester) async {
    await openCode(tester);

    expect(
      find.bySemanticsLabel('Код восстановления: K 7 Q M, 4 X P A, 9 T R B'),
      findsOneWidget,
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel(_saved)),
      isSemantics(
        label: _saved,
        hasCheckedState: true,
        isChecked: false,
        hasTapAction: true,
      ),
    );
    for (final label in ['Скопировать', 'Поделиться', _saved]) {
      final rect = tester.getSemantics(find.bySemanticsLabel(label)).rect;
      expect(rect.height, greaterThanOrEqualTo(48), reason: label);
    }
  });
}
