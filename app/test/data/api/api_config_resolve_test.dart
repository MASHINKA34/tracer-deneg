import 'package:flutter_test/flutter_test.dart';
import 'package:milionchik/data/api/api_config.dart';

void main() {
  test('debug без API_URL - локальный сервер эмулятора 10.0.2.2', () {
    final config = ApiConfig.resolve(define: '', debugBuild: true);

    expect(config.baseUrlText, 'http://10.0.2.2:8080/api/v1');
    expect(config.fromDefine, isFalse);
  });

  test('release без API_URL - понятная ошибка с подсказкой dart-define', () {
    expect(
      () => ApiConfig.resolve(define: '  ', debugBuild: false),
      throwsA(
        isA<ApiConfigException>()
            .having((e) => e.problem, 'problem', ApiConfigProblem.missing)
            .having(
              (e) => e.message,
              'message',
              allOf(
                contains('API_URL is not set'),
                contains('--dart-define=API_URL=https://'),
              ),
            ),
      ),
    );
  });

  test('release с http - ошибка: только https', () {
    expect(
      () => ApiConfig.resolve(
        define: 'http://api.milionchik.ru/api/v1',
        debugBuild: false,
      ),
      throwsA(
        isA<ApiConfigException>()
            .having((e) => e.problem, 'problem', ApiConfigProblem.insecure)
            .having((e) => e.message, 'message', contains('only over https')),
      ),
    );
  });

  test('release с https - адрес без хвостового слэша', () {
    final config = ApiConfig.resolve(
      define: 'https://api.milionchik.ru/api/v1/',
      debugBuild: false,
    );

    expect(config.baseUrlText, 'https://api.milionchik.ru/api/v1');
    expect(config.fromDefine, isTrue);
  });

  test(
    'debug с http не на 10.0.2.2 - ошибка: cleartext только для эмулятора',
    () {
      expect(
        () => ApiConfig.resolve(
          define: 'http://192.168.1.5:8080/api/v1',
          debugBuild: true,
        ),
        throwsA(
          isA<ApiConfigException>()
              .having(
                (e) => e.problem,
                'problem',
                ApiConfigProblem.cleartextHost,
              )
              .having((e) => e.message, 'message', contains('10.0.2.2')),
        ),
      );
    },
  );

  test('debug с http на 10.0.2.2 из API_URL - принимается', () {
    final config = ApiConfig.resolve(
      define: 'http://10.0.2.2:9090/api/v1',
      debugBuild: true,
    );

    expect(config.baseUrlText, 'http://10.0.2.2:9090/api/v1');
    expect(config.fromDefine, isTrue);
  });

  test('не адрес, другая схема, query или логин в адресе - invalid', () {
    for (final value in [
      'api.milionchik.ru/api/v1',
      'ftp://api.milionchik.ru/api/v1',
      'https://api.milionchik.ru/api/v1?key=1',
      'https://user:pass@api.milionchik.ru/api/v1',
      'https:///api/v1',
    ]) {
      expect(
        () => ApiConfig.resolve(define: value, debugBuild: false),
        throwsA(
          isA<ApiConfigException>().having(
            (e) => e.problem,
            'problem',
            ApiConfigProblem.invalid,
          ),
        ),
        reason: value,
      );
    }
  });

  test('таймауты: подключение 10 с, ответ 30 с', () {
    expect(apiConnectTimeout, const Duration(seconds: 10));
    expect(apiReceiveTimeout, const Duration(seconds: 30));
  });
}
