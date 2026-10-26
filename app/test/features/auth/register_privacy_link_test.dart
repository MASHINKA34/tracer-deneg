import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/core/web_links.dart';
import 'package:milionchik/data/session/session_state.dart';
import 'package:milionchik/features/auth/register_screen.dart';
import 'package:milionchik/ui/components/button.dart';
import 'package:milionchik/ui/components/snackbar.dart';

import '../../data/api/fake_api_adapter.dart';
import 'auth_harness.dart';

const String _title = 'Политика конфиденциальности';

const String _talkback =
    'Политика конфиденциальности, ссылка, откроется в браузере';

const String _failed = 'Не удалось открыть ссылку';

FakeReply _noServer(FakeCall call) =>
    throw StateError('no request expected, got ${call.method} ${call.path}');

final class _Launcher {
  _Launcher(this.reply);

  final Future<bool> Function(Uri url) reply;
  final List<String> opened = [];

  Future<bool> call(Uri url) {
    opened.add('$url');
    return reply(url);
  }
}

Future<AuthHarness> _openRegister(
  WidgetTester tester,
  _Launcher launcher, {
  Size size = const Size(360, 800),
  double textScale = 1,
}) async {
  final h = await AuthHarness.start(
    tester,
    server: _noServer,
    size: size,
    textScale: textScale,
    overrides: [urlLauncherProvider.overrideWithValue(launcher.call)],
  );
  await h.tapText('Зарегистрироваться');
  expect(find.byType(RegisterScreen), findsOneWidget);
  return h;
}

Finder get _link => find.widgetWithText(AppButton, _title);

Future<void> _tapLink(WidgetTester tester) async {
  await tester.ensureVisible(_link);
  await tester.pumpAndSettle();
  await tester.tap(_link);
  await tester.pumpAndSettle();
}

Finder _snackbar(String text) =>
    find.descendant(of: find.byType(AppSnackbar), matching: find.text(text));

void main() {
  testWidgets('под «Уже есть аккаунт? Войти» - текстовая кнопка «Политика '
      'конфиденциальности», TalkBack читает её как ссылку', (tester) async {
    final semantics = tester.ensureSemantics();
    await _openRegister(tester, _Launcher((_) async => true));

    expect(_link, findsOneWidget);
    final button = tester.widget<AppButton>(_link);
    expect(button.type, AppButtonType.text);
    expect(
      tester.getTopLeft(_link).dy,
      greaterThan(tester.getBottomLeft(find.text('Уже есть аккаунт?')).dy),
    );

    await tester.ensureVisible(_link);
    await tester.pumpAndSettle();
    final node = find.bySemanticsLabel(_talkback);
    expect(node, findsOneWidget);
    expect(
      tester.getSemantics(node),
      isSemantics(label: _talkback, isLink: true, hasTapAction: true),
    );
    expect(tester.getSemantics(node).rect.height, greaterThanOrEqualTo(48));
    expect(tester.getSemantics(node).rect.width, greaterThanOrEqualTo(48));
    semantics.dispose();
  });

  testWidgets('без входа ссылка открывает политику сервера, регистрация '
      'остаётся на экране, запросов к API нет', (tester) async {
    final launcher = _Launcher((_) async => true);
    final h = await _openRegister(tester, launcher);

    await _tapLink(tester);

    expect(launcher.opened, ['http://10.0.2.2:8080/privacy']);
    expect(find.byType(RegisterScreen), findsOneWidget);
    expect(find.byType(AppSnackbar), findsNothing);
    expect(h.session, isA<SessionAbsent>());
    expect(h.adapter.calls, isEmpty);
    expect(h.linesOf('links', Level.INFO), [
      matches(
        r'INFO  \[links\] link open page=/privacy from=register '
        r'result=launched in \d+ms$',
      ),
    ]);
  });

  testWidgets('браузер не открылся - снекбар «Не удалось открыть ссылку»', (
    tester,
  ) async {
    final launcher = _Launcher((_) async => false);
    final h = await _openRegister(tester, launcher);

    await _tapLink(tester);

    expect(launcher.opened, ['http://10.0.2.2:8080/privacy']);
    expect(_snackbar(_failed), findsOneWidget);
    expect(find.byType(RegisterScreen), findsOneWidget);
    expect(
      h.linesOf('links', Level.WARNING).single,
      contains('link open page=/privacy from=register result=failed in '),
    );
  });

  testWidgets('ошибка плагина - снекбар и warn с типом ошибки', (tester) async {
    final launcher = _Launcher(
      (_) => Future.error(
        PlatformException(code: 'channel-error', message: 'plugin not ready'),
      ),
    );
    final h = await _openRegister(tester, launcher);

    await _tapLink(tester);

    expect(_snackbar(_failed), findsOneWidget);
    final warn = h.linesOf('links', Level.WARNING).single;
    expect(warn, contains('PlatformException'));
    expect(warn, contains('plugin not ready'));
  });

  testWidgets('320 dp и шрифт 2.0: кнопка видна после прокрутки, без '
      'переполнения, нажимается', (tester) async {
    final launcher = _Launcher((_) async => true);
    await _openRegister(
      tester,
      launcher,
      size: const Size(320, 800),
      textScale: 2,
    );

    await tester.ensureVisible(_link);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.getSize(_link).height, greaterThanOrEqualTo(48));

    await _tapLink(tester);
    expect(launcher.opened, ['http://10.0.2.2:8080/privacy']);
  });
}
