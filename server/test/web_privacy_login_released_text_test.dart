import 'package:test/test.dart';

import 'support/test_support.dart';
import 'support/web_support.dart';

void main() {
  setUp(LogCapture.new);

  test(
    '/privacy: логин удалённого аккаунта освобождается, как в приложении',
    () async {
      final web = await WebHarness.start();

      final page = await web.get('/privacy');

      expect(page.status, 200);
      expect(
        page.text,
        contains(
          'Логин освобождается: его может занять другой человек, восстановить '
          'аккаунт нельзя.',
        ),
      );
      expect(page.text, isNot(contains('Логин остаётся занятым')));
      expect(
        page.text,
        isNot(contains('зарегистрироваться с ним снова нельзя')),
      );
    },
  );
}
