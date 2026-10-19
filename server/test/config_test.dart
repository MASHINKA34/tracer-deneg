import 'package:logging/logging.dart';
import 'package:server/config/config.dart';
import 'package:server/config/dotenv.dart';
import 'package:test/test.dart';

const _url = 'postgres://milionchik:s3cr%40t@127.0.0.1:5434/milionchik';
final _secret = 'x' * 40;

void main() {
  group('ServerConfig.load', () {
    test('обязательные заданы — значения по умолчанию для остального', () {
      final config = ServerConfig.load(
        environment: {'DATABASE_URL': _url, 'JWT_SECRET': _secret},
      );
      expect(config.host, '0.0.0.0');
      expect(config.port, 8080);
      expect(config.logLevel, Level.INFO);
      expect(config.database.host, '127.0.0.1');
      expect(config.database.port, 5434);
      expect(config.database.database, 'milionchik');
      expect(config.database.username, 'milionchik');
      expect(config.database.password, 's3cr@t');
      expect(config.database.sslMode, 'disable');
    });

    test('нет обязательных — все проблемы сразу', () {
      expect(
        () => ServerConfig.load(environment: {}),
        throwsA(
          isA<ConfigException>().having((e) => e.problems, 'problems', [
            startsWith('DATABASE_URL is required'),
            startsWith('JWT_SECRET is required'),
          ]),
        ),
      );
    });

    test('неверные PORT, LOG_LEVEL, короткий секрет, плохой URL', () {
      expect(
        () => ServerConfig.load(
          environment: {
            'PORT': 'abc',
            'LOG_LEVEL': 'verbose',
            'DATABASE_URL': 'mysql://u@h/db',
            'JWT_SECRET': 'short',
          },
        ),
        throwsA(
          isA<ConfigException>().having((e) => e.problems, 'problems', [
            'PORT must be a number 0..65535, got "abc"',
            'LOG_LEVEL must be one of debug|info|warn|error, got "verbose"',
            'DATABASE_URL is invalid: scheme must be postgres:// or postgresql://, got "mysql"',
            'JWT_SECRET is too short (5 chars), need ≥ 32',
          ]),
        ),
      );
    });

    test('переменные окружения важнее .env', () {
      final config = ServerConfig.load(
        environment: {'PORT': '9090', 'LOG_LEVEL': 'debug'},
        dotEnv: {
          'PORT': '8081',
          'DATABASE_URL': _url,
          'JWT_SECRET': _secret,
          'HOST': '127.0.0.1',
        },
      );
      expect(config.port, 9090);
      expect(config.logLevel, Level.FINE);
      expect(config.host, '127.0.0.1');
    });

    test('в лог-контексте секреты замаскированы', () {
      final config = ServerConfig.load(
        environment: {'DATABASE_URL': _url, 'JWT_SECRET': _secret},
      );
      final context = config.toLogContext();
      expect(
        context['db'],
        'postgres://milionchik:***@127.0.0.1:5434/milionchik?sslmode=disable',
      );
      expect(context['jwtSecret'], '***(40)');
      expect(context.toString(), isNot(contains('s3cr')));
      expect(context.toString(), isNot(contains(_secret)));
    });
  });

  group('DatabaseConfig.parse', () {
    test('порт по умолчанию 5432, sslmode из URL', () {
      final db = DatabaseConfig.parse(
        'postgresql://u:p@db/milionchik?sslmode=require',
      );
      expect(db.port, 5432);
      expect(db.sslMode, 'require');
    });

    test('ошибки формата', () {
      expect(
        () => DatabaseConfig.parse('postgres://u:p@h:1/'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => DatabaseConfig.parse('postgres://h:1/db'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => DatabaseConfig.parse('postgres://u@h/db?sslmode=prefer'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('parseDotEnv', () {
    test('комментарии, export, кавычки, BOM, CRLF', () {
      final env = parseDotEnv(
        '\uFEFF# comment\r\n'
        'PORT=8080\r\n'
        '\r\n'
        'export HOST = 127.0.0.1 \r\n'
        'A="line\\nnext \\"q\\""\r\n'
        "B='raw \\n'\r\n"
        'C=value # trailing comment\r\n'
        'D=\r\n',
      );
      expect(env.values, {
        'PORT': '8080',
        'HOST': '127.0.0.1',
        'A': 'line\nnext "q"',
        'B': r'raw \n',
        'C': 'value',
        'D': '',
      });
      expect(env.warnings, isEmpty);
    });

    test('битые строки — предупреждение с номером, без содержимого', () {
      final env = parseDotEnv('GOOD=1\nsecret-without-equals\n1BAD=2\n=x\n');
      expect(env.values, {'GOOD': '1'});
      expect(env.warnings, [
        'line 2: expected KEY=VALUE',
        'line 3: invalid key name',
        'line 4: expected KEY=VALUE',
      ]);
      expect(env.warnings.join(), isNot(contains('secret')));
    });
  });
}
