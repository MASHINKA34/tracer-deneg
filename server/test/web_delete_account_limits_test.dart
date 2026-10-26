import 'package:server/limits/trusted_proxies.dart';
import 'package:test/test.dart';

import 'support/test_support.dart';
import 'support/web_support.dart';

const _right = 'Anna-Right-Pass-Omega';
const _wrong = 'Wrong-Pass-Zeta-Kappa';

void main() {
  late LogCapture logs;
  late WebHarness web;

  Future<void> start({TrustedProxies proxies = TrustedProxies.none}) async {
    web = await WebHarness.start(trustedProxies: proxies);
    expect((await web.register('anna', _right)).status, 201);
    logs.clear();
  }

  setUp(() => logs = LogCapture());

  Future<bool> annaDeleted() async =>
      await web.count(
        "SELECT count(*)::int FROM users WHERE login = 'anna' "
        'AND deleted_at IS NULL',
      ) ==
      0;

  void expectTooMany(WebPage page, String retryAfter, String reason) {
    expect(page.status, 429, reason: '$page');
    expect(page.contentType, 'text/html; charset=utf-8');
    expect(page.headers['retry-after'], retryAfter);
    expect(page.headers['cache-control'], 'no-store');
    expect(
      page.headers['content-security-policy'],
      contains("default-src 'none'"),
    );
    expect(page.headers['x-content-type-options'], 'nosniff');
    expect(page.text, contains('Слишком много попыток'));
    expect(page.text, contains(reason));
    expect(page.text, contains('Аккаунт не удалён'));
    expect(page.html, contains('<a href="/delete-account">'));
  }

  group('5 неудач на логин за 15 минут', () {
    test('пять неверных паролей → 401, шестая попытка → 429-страница с '
        'Retry-After 900, верный пароль тоже 429 и аккаунт цел', () async {
      await start();
      for (final login in ['anna', 'ANNA', ' Anna ', 'anna', 'aNNa']) {
        final page = await web.deleteByForm(login, _wrong);
        expect(page.status, 401, reason: '$page');
      }

      final sixth = await web.deleteByForm('anna', _wrong);
      expectTooMany(
        sixth,
        '900',
        'Слишком много неудачных попыток. Попробуй через 15 мин.',
      );
      final right = await web.deleteByForm('anna', _right);
      expectTooMany(right, '900', 'Попробуй через 15 мин.');
      expect(await annaDeleted(), isFalse);

      expect(
        logs.text,
        contains(
          'WARN  [web] delete-account login attempts exhausted login=an*** '
          'failures=5/5 window=15m → next attempts blocked for 900s',
        ),
      );
      expect(
        logs.text,
        contains(
          'WARN  [web] delete-account form blocked: login attempts limit hit '
          'login=an*** failures=5/5 window=15m retryAfter=900s '
          'ip=198.51.100.1',
        ),
      );
      expect(logs.text, contains('POST /delete-account 429'));
    });

    test('счётчик общий со входом /api/v1/auth/login: 3 неудачи входа и 2 '
        'через форму → заблокированы и форма, и вход', () async {
      await start();
      for (var i = 0; i < 3; i++) {
        expect((await web.login('anna', _wrong)).status, 401);
      }
      for (var i = 0; i < 2; i++) {
        expect((await web.deleteByForm('anna', _wrong)).status, 401);
      }

      expectTooMany(
        await web.deleteByForm('anna', _right),
        '900',
        'Попробуй через 15 мин.',
      );
      final login = await web.login('anna', _right);
      expect(login.status, 429, reason: '$login');
      expect(login.errorCode, 'too_many_attempts');
      expect(await annaDeleted(), isFalse);
    });

    test('через 15 минут (подмена часов) форма снова удаляет; за секунду до '
        '— 429 с Retry-After 1; удаление сбрасывает счётчик', () async {
      await start();
      for (var i = 0; i < 5; i++) {
        expect((await web.deleteByForm('anna', _wrong)).status, 401);
      }

      web.clock.advance(const Duration(minutes: 14, seconds: 59));
      expectTooMany(
        await web.deleteByForm('anna', _right),
        '1',
        'Попробуй через 1 с.',
      );

      web.clock.advance(const Duration(seconds: 1));
      final ok = await web.deleteByForm('anna', _right);
      expect(ok.status, 200, reason: '$ok');
      expect(await annaDeleted(), isTrue);
      expect(web.limits.loginFailures.count('anna'), 0);
    });

    test('логин неверного формата в лимит по логину не попадает', () async {
      await start();
      for (var i = 0; i < 7; i++) {
        final page = await web.deleteByForm('a b', _wrong);
        expect(page.status, 401, reason: 'attempt ${i + 1}: $page');
      }
      expect(web.limits.loginFailures.trackedKeys, 0);
      expect(
        logs.text,
        contains(
          'DEBUG [web] delete-account attempts not tracked: login format '
          'invalid',
        ),
      );
    });
  });

  group('30 запросов в минуту с IP, как у /api/v1/auth/*', () {
    test('31-й POST формы с одного IP → 429-страница с Retry-After 60, '
        'другой IP проходит, вход в API с того же IP тоже 429', () async {
      await start();
      for (var i = 0; i < 30; i++) {
        final page = await web.postForm(
          '/delete-account',
          fields: {'login': '', 'password': ''},
        );
        expect(page.status, 400, reason: 'request ${i + 1}: $page');
      }

      expectTooMany(
        await web.deleteByForm('anna', _right),
        '60',
        'Слишком много запросов. Попробуй через 1 мин.',
      );
      expect(await annaDeleted(), isFalse);
      final api = await web.login('anna', _right);
      expect(api.status, 429, reason: '$api');

      final otherIp = await web.deleteByForm(
        'anna',
        _right,
        ip: '198.51.100.77',
      );
      expect(otherIp.status, 200, reason: '$otherIp');
      expect(
        logs.text,
        contains(
          'WARN  [web] delete-account form blocked: ip rate limit hit '
          'limiter=auth-ip ip=198.51.100.1 limit=30/60s retryAfter=60s',
        ),
      );
    });

    test('GET страницы в лимит не идёт', () async {
      await start();
      for (var i = 0; i < 40; i++) {
        expect((await web.get('/delete-account')).status, 200);
      }
      expect(web.limits.authRequests.count('198.51.100.1'), 0);
    });

    test(
      'за доверенным прокси лимит считается по IP из X-Forwarded-For',
      () async {
        await start(proxies: TrustedProxies.parse('10.0.0.2'));
        for (var i = 0; i < 30; i++) {
          final page = await web.postForm(
            '/delete-account',
            fields: {'login': '', 'password': ''},
            ip: '10.0.0.2',
            forwardedFor: '203.0.113.5',
          );
          expect(page.status, 400);
        }

        final blocked = await web.postForm(
          '/delete-account',
          fields: {'login': '', 'password': ''},
          ip: '10.0.0.2',
          forwardedFor: '203.0.113.5',
        );
        expect(blocked.status, 429);
        final other = await web.postForm(
          '/delete-account',
          fields: {'login': '', 'password': ''},
          ip: '10.0.0.2',
          forwardedFor: '203.0.113.6',
        );
        expect(other.status, 400);
        expect(logs.text, contains('ip=203.0.113.5 limit=30/60s'));
      },
    );
  });
}
