import 'dart:convert';
import 'dart:io';

import 'package:cryptography/dart.dart' show DartSha256;
import 'package:server/config/config.dart';
import 'package:server/server_app.dart';
import 'package:server/web/web_page.dart';
import 'package:test/test.dart';

import 'support/test_support.dart';
import 'support/web_support.dart';

const _url =
    'postgres://milionchik:milionchik@127.0.0.1:5434/milionchik?sslmode=disable';
const _secret = 'privacy-config-secret-0123456789-abcdef';

void main() {
  late LogCapture logs;

  setUp(() => logs = LogCapture());

  group('GET /privacy', () {
    test('200 text/html; charset=utf-8, контакт и оператор из настроек '
        'экранированы', () async {
      final web = await WebHarness.start(
        privacy: const PrivacySettings(
          contact: 'privacy@example.test & t.me/Op_Contact_Qx',
          operator: 'Оператор <Квазар> "Тест"',
        ),
      );

      final page = await web.get('/privacy');

      expect(page.status, 200, reason: '$page');
      expect(page.contentType, 'text/html; charset=utf-8');
      expect(
        page.html,
        contains('privacy@example.test &amp; t.me&#47;Op_Contact_Qx'),
      );
      expect(page.html, contains('Оператор &lt;Квазар&gt; &quot;Тест&quot;'));
      expect(page.html, isNot(contains('<Квазар>')));
      expect(page.html, isNot(contains(notSpecified)));
    });

    test('пустые настройки → «не указан» у оператора и у контакта', () async {
      final web = await WebHarness.start();

      final page = await web.get('/privacy');

      expect(page.status, 200);
      expect(page.text, contains('Оператор данных: не указан'));
      expect(page.text, contains('Контакт для вопросов о данных: не указан'));
    });

    test(
      'сроки и удаление совпадают с тем, что делает сервер: текст '
      'удалённых записей, названия устройств, общий бюджет без участников',
      () async {
        final web = await WebHarness.start();

        final text = (await web.get('/privacy')).text;

        for (final fragment in [
          'Название устройства, с которого выполнен вход: пока вход активен и '
              'ещё 90 дней после выхода.',
          'Удалённые траты, категории и регулярные траты: текст (комментарий, '
              'название) стирается сразу. Остаётся пометка без текста (сумма, '
              'дата, категория), чтобы удаление дошло до всех телефонов. Она '
              'хранится, пока существует бюджет.',
          'все входы на устройствах завершаются, названия устройств стираются '
              'сразу.',
          'если других участников нет, бюджет удаляется со всеми тратами, '
              'категориями и регулярными тратами.',
        ]) {
          expect(text, contains(fragment), reason: fragment);
        }
      },
    );

    test(
      'содержание: какие данные, зачем, где, сколько, как удалить',
      () async {
        final web = await WebHarness.start();

        final text = (await web.get('/privacy')).text;
        final html = (await web.get('/privacy')).html;

        for (final fragment in [
          'Какие данные хранятся',
          'логин и имя',
          'Дата рождения',
          'Траты',
          'Отчёты об ошибках',
          'Зачем они нужны',
          'собственном сервере',
          'пока ты не удалишь аккаунт',
          '30 дней',
          'Профиль → «Удалить аккаунт»',
          'Удалённый участник',
        ]) {
          expect(text, contains(fragment), reason: fragment);
        }
        expect(html, contains('<a href="/delete-account">'));
        expect(html, startsWith('<!doctype html>'));
        expect(html, contains('<html lang="ru">'));
      },
    );

    test('без внешних ресурсов, CSS внутри и разрешён в CSP по хэшу, '
        'заголовки безопасности', () async {
      final web = await WebHarness.start();

      final page = await web.get('/privacy');

      expect(page.html, isNot(contains('<script')));
      expect(page.html, isNot(contains('<link')));
      expect(page.html, isNot(contains('<img')));
      expect(page.html, isNot(contains('src=')));
      expect(page.html, isNot(contains('url(')));
      expect(page.html, isNot(contains('@import')));
      expect(page.html, isNot(contains('http://')));
      expect(page.html, isNot(contains('https://')));

      final style = RegExp(
        r'<style>(.*?)</style>',
        dotAll: true,
      ).allMatches(page.html).toList();
      expect(style, hasLength(1));
      final hash = base64.encode(
        const DartSha256().hashSync(utf8.encode(style.single.group(1)!)).bytes,
      );

      final csp = page.headers['content-security-policy']!;
      expect(csp, contains("default-src 'none'"));
      expect(csp, contains("style-src 'sha256-$hash'"));
      expect(csp, contains("form-action 'self'"));
      expect(csp, contains("frame-ancestors 'none'"));
      expect(csp, isNot(contains('unsafe-inline')));
      expect(page.headers['x-content-type-options'], 'nosniff');
      expect(page.headers['x-frame-options'], 'DENY');
      expect(page.headers['referrer-policy'], 'no-referrer');
    });

    test('показ страницы — debug-строка [web] без значений контакта и '
        'оператора', () async {
      final web = await WebHarness.start(
        privacy: const PrivacySettings(
          contact: 'Contact-Value-Lambda',
          operator: 'Operator-Value-Sigma',
        ),
      );
      logs.clear();

      await web.get('/privacy');

      expect(
        logs.lines,
        contains(
          matches(
            r'DEBUG \[web\] page shown /privacy status=200 '
            r'contact=set operator=set bytes=\d+',
          ),
        ),
      );
      final bytes = RegExp(r'page shown /privacy .* bytes=(\d+)')
          .firstMatch(logs.text)!
          .group(1);
      expect(
        logs.text,
        contains(RegExp('GET /privacy 200 in \\d+ms size=$bytes ')),
      );
      expect(logs.text, isNot(contains('Contact-Value-Lambda')));
      expect(logs.text, isNot(contains('Operator-Value-Sigma')));
    });
  });

  group('настройки PRIVACY_CONTACT и PRIVACY_OPERATOR', () {
    test('читаются из окружения и .env, пробелы по краям срезаются, '
        'пустые → null', () {
      final filled = ServerConfig.load(
        environment: {
          'DATABASE_URL': _url,
          'JWT_SECRET': _secret,
          'INVITE_CODE_SECRET': 'invite-code-secret-0123456789-abcdef',
          'PRIVACY_CONTACT': '  privacy@example.test ',
        },
        dotEnv: {'PRIVACY_OPERATOR': 'Иван Петров'},
      );
      expect(filled.privacyContact, 'privacy@example.test');
      expect(filled.privacyOperator, 'Иван Петров');
      expect(filled.toLogContext()['privacyContact'], 'set');
      expect(filled.toLogContext()['privacyOperator'], 'set');
      expect(filled.toLogContext().toString(), isNot(contains('Иван')));

      final empty = ServerConfig.load(
        environment: {
          'DATABASE_URL': _url,
          'JWT_SECRET': _secret,
          'INVITE_CODE_SECRET': 'invite-code-secret-0123456789-abcdef',
          'PRIVACY_CONTACT': '   ',
        },
      );
      expect(empty.privacyContact, isNull);
      expect(empty.privacyOperator, isNull);
      expect(empty.toLogContext()['privacyContact'], 'empty');
    });

    Future<(int, String)> fetchPrivacy(RunningServer server) async {
      final http = HttpClient();
      addTearDown(() => http.close(force: true));
      final request = await http.get('127.0.0.1', server.port, '/privacy');
      final response = await request.close();
      return (
        response.statusCode,
        await response.transform(utf8.decoder).join(),
      );
    }

    test('запущенный сервер берёт значения из настроек для /privacy, warn '
        'при старте нет', () async {
      final server = await startServer(
        ServerConfig.load(
          environment: {
            'HOST': '127.0.0.1',
            'PORT': '0',
            'DATABASE_URL': await createScratchDatabase(),
            'JWT_SECRET': _secret,
            'INVITE_CODE_SECRET': 'invite-code-secret-0123456789-abcdef',
            'PRIVACY_CONTACT': 'privacy@example.test',
            'PRIVACY_OPERATOR': 'Оператор Омега',
          },
        ),
        dbConnectAttempts: 1,
      );
      addTearDown(() => server.shutdown('test'));

      final (status, html) = await fetchPrivacy(server);

      expect(status, 200);
      expect(html, contains('privacy@example.test'));
      expect(html, contains('Оператор Омега'));
      expect(
        logs.text,
        contains(
          'INFO  [server] web pages ready paths=/privacy,/delete-account '
          'contact=set operator=set',
        ),
      );
      expect(logs.text, isNot(contains('is empty')));
    });

    test('пустые значения → warn при старте по каждой переменной, на '
        'странице «не указан»', () async {
      final server = await startServer(
        ServerConfig.load(
          environment: {
            'HOST': '127.0.0.1',
            'PORT': '0',
            'DATABASE_URL': await createScratchDatabase(),
            'JWT_SECRET': _secret,
            'INVITE_CODE_SECRET': 'invite-code-secret-0123456789-abcdef',
          },
        ),
        dbConnectAttempts: 1,
      );
      addTearDown(() => server.shutdown('test'));

      final (status, html) = await fetchPrivacy(server);

      expect(status, 200);
      expect(html, contains('<strong>Оператор данных:</strong> не указан'));
      for (final (name, pages) in [
        ('PRIVACY_CONTACT', '/privacy and /delete-account show'),
        ('PRIVACY_OPERATOR', '/privacy shows'),
      ]) {
        expect(
          logs.text,
          contains(
            'WARN  [server] $name is empty → $pages «не указан»; '
            'set it in .env on the server before deploy',
          ),
        );
      }
    });
  });
}
