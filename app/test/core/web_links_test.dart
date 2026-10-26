import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/core/web_links.dart';
import 'package:milionchik/data/api/api_config.dart';
import 'package:milionchik/data/api/api_providers.dart';

import '../data/api/fake_api_adapter.dart';

final class _FakeLauncher {
  _FakeLauncher(this.reply);

  final Future<bool> Function(Uri url) reply;
  final List<Uri> opened = [];

  Future<bool> call(Uri url) {
    opened.add(url);
    return reply(url);
  }
}

void main() {
  group('адрес страницы из API_URL', () {
    const cases = {
      'https://x.ru/api/v1': 'https://x.ru',
      'https://x.ru/api/v1/': 'https://x.ru',
      'http://10.0.2.2:8080/api/v1': 'http://10.0.2.2:8080',
    };

    for (final MapEntry(key: api, value: site) in cases.entries) {
      test('$api → $site/privacy и $site/delete-account', () {
        final config = ApiConfig.resolve(define: api, debugBuild: true);
        final raw = Uri.parse(api);

        for (final base in [config.baseUrl, raw]) {
          expect(webPageUrl(base, WebPage.privacy).toString(), '$site/privacy');
          expect(
            webPageUrl(base, WebPage.deleteAccount).toString(),
            '$site/delete-account',
          );
        }
      });
    }

    test('явный порт https сохраняется, путь API отбрасывается', () {
      expect(
        webPageUrl(
          Uri.parse('https://x.ru:8443/srv/api/v1'),
          WebPage.privacy,
        ).toString(),
        'https://x.ru:8443/privacy',
      );
    });

    test('debug без API_URL → http://10.0.2.2:8080/privacy', () {
      final config = ApiConfig.resolve(define: '', debugBuild: true);
      expect(
        webPageUrl(config.baseUrl, WebPage.privacy).toString(),
        'http://10.0.2.2:8080/privacy',
      );
    });
  });

  group('открытие во внешнем браузере', () {
    late LogCapture logs;

    setUp(() => logs = LogCapture());
    tearDown(() => logs.dispose());

    ProviderContainer containerWith(_FakeLauncher launcher) =>
        ProviderContainer.test(
          overrides: [
            apiConfigProvider.overrideWithValue(
              ApiConfig.resolve(
                define: 'https://x.ru/api/v1',
                debugBuild: false,
              ),
            ),
            urlLauncherProvider.overrideWithValue(launcher.call),
          ],
        );

    List<String> lines([Level from = Level.ALL]) => logs.linesOf('links', from);

    test(
      'открылось: адрес страницы, info с путём, откуда, launched и мс',
      () async {
        final launcher = _FakeLauncher((_) async => true);
        final links = containerWith(launcher).read(webLinksProvider);

        expect(
          await links.open(WebPage.privacy, from: WebLinkSource.profile),
          isTrue,
        );
        expect(
          await links.open(
            WebPage.deleteAccount,
            from: WebLinkSource.deleteAccount,
          ),
          isTrue,
        );

        expect(launcher.opened.map((u) => '$u'), [
          'https://x.ru/privacy',
          'https://x.ru/delete-account',
        ]);
        final info = lines(Level.INFO);
        expect(info, hasLength(2));
        expect(
          info[0],
          matches(
            RegExp(
              r'INFO  \[links\] link open page=/privacy from=profile '
              r'result=launched in \d+ms$',
            ),
          ),
        );
        expect(
          info[1],
          matches(
            RegExp(
              r'INFO  \[links\] link open page=/delete-account '
              r'from=deleteAccount result=launched in \d+ms$',
            ),
          ),
        );
        expect(lines(Level.WARNING), isEmpty);
      },
    );

    test('браузера нет (launcher вернул false): false и warn failed с '
        'адресом', () async {
      final launcher = _FakeLauncher((_) async => false);
      final links = containerWith(launcher).read(webLinksProvider);

      expect(
        await links.open(WebPage.privacy, from: WebLinkSource.register),
        isFalse,
      );

      final warn = lines(Level.WARNING);
      expect(warn, hasLength(1));
      expect(
        warn.single,
        matches(
          RegExp(
            r'WARN  \[links\] link open page=/privacy from=register '
            r'result=failed in \d+ms: no app on the phone took '
            r'url=https://x\.ru/privacy → error snackbar$',
          ),
        ),
      );
    });

    test('ошибка плагина: false, warn с типом, сообщением и стеком', () async {
      final launcher = _FakeLauncher(
        (_) => Future.error(
          PlatformException(
            code: 'ACTIVITY_NOT_FOUND',
            message: 'No Activity found to handle Intent',
          ),
        ),
      );
      final links = containerWith(launcher).read(webLinksProvider);

      expect(
        await links.open(
          WebPage.deleteAccount,
          from: WebLinkSource.deleteAccount,
        ),
        isFalse,
      );

      final warn = lines(Level.WARNING);
      expect(warn, hasLength(1));
      expect(
        warn.single,
        contains(
          'WARN  [links] link open page=/delete-account from=deleteAccount '
          'result=failed in ',
        ),
      );
      expect(
        warn.single,
        contains('url=https://x.ru/delete-account: PlatformException'),
      );
      expect(warn.single, contains('ACTIVITY_NOT_FOUND'));
      expect(warn.single, contains('No Activity found to handle Intent'));
      expect(warn.single, contains('→ error snackbar'));
      expect(warn.single, contains('stack:'));
    });
  });
}
