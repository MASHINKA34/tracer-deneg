import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/core/web_links.dart';
import 'package:milionchik/data/session/session_providers.dart';
import 'package:milionchik/data/session/session_state.dart';
import 'package:milionchik/features/profile/delete_account_screen.dart';
import 'package:milionchik/features/profile/profile_screen.dart';
import 'package:milionchik/ui/components/button.dart';
import 'package:milionchik/ui/components/snackbar.dart';

import 'profile_harness.dart';

const String _pageTitle = 'Страница удаления аккаунта';

const String _privacyTitle = 'Политика конфиденциальности';

const String _note =
    'Удалить аккаунт можно и без приложения — на странице удаления на сайте '
    'сервера — ссылки ниже. Это требование Google Play.';

const String _failed = 'Не удалось открыть ссылку';

String _talkback(String title) => '$title, ссылка, откроется в браузере';

final class _Launcher {
  _Launcher(this.reply);

  final Future<bool> Function(Uri url) reply;
  final List<String> opened = [];

  Future<bool> call(Uri url) {
    opened.add('$url');
    return reply(url);
  }
}

Future<ProfileHarness> _open(
  WidgetTester tester,
  _Launcher launcher, {
  Size size = const Size(360, 800),
  double textScale = 1,
}) async {
  final h = await ProfileHarness.start(
    tester,
    size: size,
    textScale: textScale,
    overrides: [urlLauncherProvider.overrideWithValue(launcher.call)],
  );
  await h.openProfile();
  await h.tap(h.row('Удалить аккаунт'));
  expect(find.byType(DeleteAccountScreen), findsOneWidget);
  return h;
}

Finder _button(String label) => find.widgetWithText(AppButton, label);

Finder _snackbar(String text) =>
    find.descendant(of: find.byType(AppSnackbar), matching: find.text(text));

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testWidgets('подпись кончается «— ссылки ниже», под ней две текстовые '
      'кнопки-ссылки, TalkBack читает их как ссылки', (tester) async {
    final semantics = tester.ensureSemantics();
    await _open(tester, _Launcher((_) async => true));

    expect(find.text(_note), findsOneWidget);
    final noteBottom = tester.getBottomLeft(find.text(_note)).dy;
    final page = _button(_pageTitle);
    final privacy = _button(_privacyTitle);
    expect(tester.widget<AppButton>(page).type, AppButtonType.text);
    expect(tester.widget<AppButton>(privacy).type, AppButtonType.text);
    expect(tester.getTopLeft(page).dy, greaterThan(noteBottom));
    expect(
      tester.getTopLeft(privacy).dy,
      greaterThanOrEqualTo(tester.getBottomLeft(page).dy),
    );

    for (final title in [_pageTitle, _privacyTitle]) {
      await tester.ensureVisible(_button(title));
      await tester.pumpAndSettle();
      final node = find.bySemanticsLabel(_talkback(title));
      expect(node, findsOneWidget, reason: title);
      expect(
        tester.getSemantics(node),
        isSemantics(label: _talkback(title), isLink: true, hasTapAction: true),
        reason: title,
      );
      expect(
        tester.getSemantics(node).rect.height,
        greaterThanOrEqualTo(48),
        reason: title,
      );
    }
    semantics.dispose();
  });

  testWidgets('«Страница удаления аккаунта» открывает /delete-account, '
      '«Политика конфиденциальности» - /privacy; «Передумал» - ничего не '
      'удалено', (tester) async {
    final launcher = _Launcher((_) async => true);
    final h = await _open(tester, launcher);

    await h.tap(_button(_pageTitle));
    await h.tap(_button(_privacyTitle));

    expect(launcher.opened, [
      'http://10.0.2.2:8080/delete-account',
      'http://10.0.2.2:8080/privacy',
    ]);
    expect(find.byType(DeleteAccountScreen), findsOneWidget);
    expect(find.byType(AppSnackbar), findsNothing);
    expect(h.linesOf('links', Level.INFO), [
      matches(
        r'INFO  \[links\] link open page=/delete-account '
        r'from=deleteAccount result=launched in \d+ms$',
      ),
      matches(
        r'INFO  \[links\] link open page=/privacy from=deleteAccount '
        r'result=launched in \d+ms$',
      ),
    ]);

    await h.tap(_button('Передумал'));

    expect(find.byType(DeleteAccountScreen), findsNothing);
    expect(find.byType(ProfileScreen), findsOneWidget);
    expect(h.adapter.calls, isEmpty);
    expect(h.container.read(sessionProvider), isA<SessionActive>());
  });

  testWidgets('браузер не открылся - снекбар «Не удалось открыть ссылку», '
      'экран и пароль на месте', (tester) async {
    final launcher = _Launcher((_) async => false);
    final h = await _open(tester, launcher);
    await h.enter('Введи пароль, чтобы подтвердить', 'parol-12');

    await h.tap(_button(_pageTitle));

    expect(launcher.opened, ['http://10.0.2.2:8080/delete-account']);
    expect(_snackbar(_failed), findsOneWidget);
    expect(find.byType(DeleteAccountScreen), findsOneWidget);
    expect(
      tester
          .widget<TextField>(h.input('Введи пароль, чтобы подтвердить'))
          .controller!
          .text,
      'parol-12',
    );
    expect(
      h.linesOf('links', Level.WARNING).single,
      contains(
        'link open page=/delete-account from=deleteAccount result=failed in ',
      ),
    );
    expect(h.adapter.calls, isEmpty);
  });

  testWidgets('ошибка плагина - снекбар и warn с типом ошибки', (tester) async {
    final launcher = _Launcher(
      (_) => Future.error(
        PlatformException(code: 'channel-error', message: 'plugin not ready'),
      ),
    );
    final h = await _open(tester, launcher);

    await h.tap(_button(_privacyTitle));

    expect(_snackbar(_failed), findsOneWidget);
    final warn = h.linesOf('links', Level.WARNING).single;
    expect(warn, contains('page=/privacy from=deleteAccount'));
    expect(warn, contains('PlatformException'));
    expect(warn, contains('plugin not ready'));
  });

  testWidgets('320 dp и шрифт 2.0: кнопки без переполнения, выше 48 dp и '
      'нажимаются', (tester) async {
    final launcher = _Launcher((_) async => true);
    final h = await _open(
      tester,
      launcher,
      size: const Size(320, 800),
      textScale: 2,
    );

    for (final title in [_pageTitle, _privacyTitle]) {
      await tester.ensureVisible(_button(title));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: title);
      expect(
        tester.getSize(_button(title)).height,
        greaterThanOrEqualTo(48),
        reason: title,
      );
      await h.tap(_button(title));
    }
    expect(launcher.opened, [
      'http://10.0.2.2:8080/delete-account',
      'http://10.0.2.2:8080/privacy',
    ]);
  });
}
