import 'dart:io';

import 'package:server/config/config.dart';
import 'package:server/limits/trusted_proxies.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'support/limits_support.dart';
import 'support/test_support.dart';

const _url = 'postgres://milionchik:milionchik@127.0.0.1:5434/milionchik';
final _secret = 'x' * 40;

Request _request(String? peer, {String? forwardedFor}) => Request(
  'POST',
  Uri.parse('http://localhost/api/v1/auth/login'),
  headers: {'x-forwarded-for': ?forwardedFor},
  context: {
    if (peer != null) 'shelf.io.connection_info': FakeConnectionInfo(peer),
  },
);

void main() {
  late LogCapture logs;
  setUp(() => logs = LogCapture());

  group('TrustedProxies.parse', () {
    test('пусто или не задано → никому не доверяем', () {
      expect(TrustedProxies.parse(null).isEmpty, isTrue);
      expect(TrustedProxies.parse('  ').isEmpty, isTrue);
      expect(TrustedProxies.parse('').describe(), 'none');
    });

    test('адреса и подсети IPv4/IPv6 через запятую или пробел', () {
      final trusted = TrustedProxies.parse(
        '10.0.0.2, 172.16.0.0/12 ::1,fd00::/8',
      );
      expect(trusted.ranges, hasLength(4));
      expect(trusted.describe(), '10.0.0.2,172.16.0.0/12,::1,fd00::/8');
      expect(trusted.contains(InternetAddress('10.0.0.2')), isTrue);
      expect(trusted.contains(InternetAddress('10.0.0.3')), isFalse);
      expect(trusted.contains(InternetAddress('172.18.0.5')), isTrue);
      expect(trusted.contains(InternetAddress('172.32.0.1')), isFalse);
      expect(trusted.contains(InternetAddress('::1')), isTrue);
      expect(trusted.contains(InternetAddress('fd12:3456::1')), isTrue);
      expect(trusted.contains(InternetAddress('2001:db8::1')), isFalse);
      expect(trusted.contains(InternetAddress('::ffff:10.0.0.2')), isTrue);
    });

    test('неверные записи → FormatException со списком', () {
      expect(
        () => TrustedProxies.parse('10.0.0.2, caddy, 10.0.0.0/33, 1.2.3.4/x'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('"caddy"'),
              contains('"10.0.0.0/33"'),
              contains('"1.2.3.4/x"'),
              isNot(contains('"10.0.0.2"')),
            ),
          ),
        ),
      );
    });
  });

  group('TRUSTED_PROXIES в конфиге', () {
    test('по умолчанию пусто; значение попадает в лог-контекст', () {
      final plain = ServerConfig.load(
        environment: {'DATABASE_URL': _url, 'JWT_SECRET': _secret},
      );
      expect(plain.trustedProxies.isEmpty, isTrue);
      expect(plain.toLogContext()['trustedProxies'], 'none');

      final behindCaddy = ServerConfig.load(
        environment: {
          'DATABASE_URL': _url,
          'JWT_SECRET': _secret,
          'TRUSTED_PROXIES': '172.16.0.0/12',
        },
      );
      expect(behindCaddy.trustedProxies.describe(), '172.16.0.0/12');
      expect(behindCaddy.toLogContext()['trustedProxies'], '172.16.0.0/12');
    });

    test('неверное значение → ConfigException', () {
      expect(
        () => ServerConfig.load(
          environment: {
            'DATABASE_URL': _url,
            'JWT_SECRET': _secret,
            'TRUSTED_PROXIES': 'caddy',
          },
        ),
        throwsA(
          isA<ConfigException>().having((e) => e.problems, 'problems', [
            startsWith('TRUSTED_PROXIES is invalid: invalid entries "caddy"'),
          ]),
        ),
      );
    });
  });

  group('clientIp', () {
    final trusted = TrustedProxies.parse('10.0.0.2, 10.0.1.0/24');

    test('без сведений о соединении → «-»', () {
      expect(clientIp(_request(null), trusted), '-');
    });

    test('прямой запрос → адрес соединения, заголовок игнорируется', () {
      expect(
        clientIp(
          _request('198.51.100.7', forwardedFor: '203.0.113.5'),
          trusted,
        ),
        '198.51.100.7',
      );
      expect(
        logs.text,
        contains(
          'X-Forwarded-For ignored: peer 198.51.100.7 is not a trusted proxy',
        ),
      );
    });

    test('без настройки доверенных — заголовок игнорируется всегда', () {
      expect(
        clientIp(
          _request('10.0.0.2', forwardedFor: '203.0.113.5'),
          TrustedProxies.none,
        ),
        '10.0.0.2',
      );
    });

    test('от доверенного прокси → самый правый недоверенный адрес', () {
      expect(
        clientIp(_request('10.0.0.2', forwardedFor: '203.0.113.5'), trusted),
        '203.0.113.5',
      );
      expect(
        clientIp(
          _request('10.0.0.2', forwardedFor: '1.1.1.1, 203.0.113.5, 10.0.1.7'),
          trusted,
        ),
        '203.0.113.5',
      );
      expect(
        logs.text,
        contains(
          'client ip from X-Forwarded-For peer=10.0.0.2 (trusted) hops=3 '
          'ip=203.0.113.5',
        ),
      );
    });

    test('порт и квадратные скобки в записи, IPv4 внутри IPv6', () {
      expect(
        clientIp(
          _request('::ffff:10.0.0.2', forwardedFor: '203.0.113.5:4711'),
          trusted,
        ),
        '203.0.113.5',
      );
      expect(
        clientIp(
          _request('10.0.0.2', forwardedFor: '[2001:db8::1]:443'),
          trusted,
        ),
        '2001:db8::1',
      );
    });

    test('мусор в заголовке → остаёмся на последнем известном адресе', () {
      expect(
        clientIp(_request('10.0.0.2', forwardedFor: 'unknown'), trusted),
        '10.0.0.2',
      );
      expect(
        clientIp(
          _request('10.0.0.2', forwardedFor: 'garbage, 10.0.1.7'),
          trusted,
        ),
        '10.0.1.7',
      );
    });
  });
}
