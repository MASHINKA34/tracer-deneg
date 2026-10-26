import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/core/web_links.dart';
import 'package:milionchik/features/profile/profile_screen.dart';
import 'package:milionchik/ui/components/list_row.dart';
import 'package:milionchik/ui/components/snackbar.dart';
import 'package:milionchik/ui/icons/app_icon.dart';

import 'profile_harness.dart';

const String _title = 'Политика конфиденциальности';

const String _talkback =
    'Политика конфиденциальности, ссылка, откроется в браузере';

const String _failed = 'Не удалось открыть ссылку';

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
  expect(find.byType(ProfileScreen), findsOneWidget);
  return h;
}

Finder _snackbar(String text) =>
    find.descendant(of: find.byType(AppSnackbar), matching: find.text(text));

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testWidgets('строка «Политика конфиденциальности» с замком стоит после '
      '«Отправить логи разработчику», TalkBack читает её как ссылку', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final h = await _open(tester, _Launcher((_) async => true));

    final titles = tester
        .widgetList<ListRow>(find.byType(ListRow))
        .map((r) => r.title)
        .toList();
    expect(
      titles.indexOf(_title),
      titles.indexOf('Отправить логи разработчику') + 1,
    );
    expect(titles.indexOf('Выйти'), titles.indexOf(_title) + 1);
    final row = tester.widget<ListRow>(h.row(_title));
    expect(row.icon, AppIcons.lock);
    expect(row.danger, isFalse);
    expect(row.value, isNull);

    await tester.ensureVisible(h.row(_title));
    await tester.pumpAndSettle();
    final node = find.bySemanticsLabel(_talkback);
    expect(node, findsOneWidget);
    expect(
      tester.getSemantics(node),
      isSemantics(label: _talkback, isLink: true, hasTapAction: true),
    );
    expect(tester.getSize(h.row(_title)).height, greaterThanOrEqualTo(48));
    semantics.dispose();
  });

  testWidgets('нажатие открывает политику сервера во внешнем браузере, '
      'снекбара нет, в логе info с путём и источником', (tester) async {
    final launcher = _Launcher((_) async => true);
    final h = await _open(tester, launcher);

    await h.tap(h.row(_title));

    expect(launcher.opened, ['http://10.0.2.2:8080/privacy']);
    expect(find.byType(AppSnackbar), findsNothing);
    expect(find.byType(ProfileScreen), findsOneWidget);
    expect(h.adapter.calls, isEmpty);
    expect(h.linesOf('links', Level.INFO), [
      matches(
        r'INFO  \[links\] link open page=/privacy from=profile '
        r'result=launched in \d+ms$',
      ),
    ]);
  });

  testWidgets('браузер не открылся - снекбар «Не удалось открыть ссылку» '
      'и warn', (tester) async {
    final launcher = _Launcher((_) async => false);
    final h = await _open(tester, launcher);

    await h.tap(h.row(_title));

    expect(launcher.opened, ['http://10.0.2.2:8080/privacy']);
    expect(_snackbar(_failed), findsOneWidget);
    expect(h.linesOf('links', Level.WARNING), [
      contains('link open page=/privacy from=profile result=failed in '),
    ]);
  });

  testWidgets('ошибка плагина - тот же снекбар, warn с типом и сообщением', (
    tester,
  ) async {
    final launcher = _Launcher(
      (_) => Future.error(
        PlatformException(code: 'channel-error', message: 'plugin not ready'),
      ),
    );
    final h = await _open(tester, launcher);

    await h.tap(h.row(_title));

    expect(_snackbar(_failed), findsOneWidget);
    final warn = h.linesOf('links', Level.WARNING).single;
    expect(warn, contains('PlatformException'));
    expect(warn, contains('plugin not ready'));
  });

  testWidgets('320 dp и шрифт 2.0: строка без переполнения, выше 48 dp и '
      'нажимается', (tester) async {
    final launcher = _Launcher((_) async => true);
    final h = await _open(
      tester,
      launcher,
      size: const Size(320, 800),
      textScale: 2,
    );

    await tester.ensureVisible(h.row(_title));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.getSize(h.row(_title)).height, greaterThanOrEqualTo(48));

    await h.tap(h.row(_title));
    expect(launcher.opened, ['http://10.0.2.2:8080/privacy']);
  });
}
