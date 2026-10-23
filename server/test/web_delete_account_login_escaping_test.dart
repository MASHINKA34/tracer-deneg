import 'package:test/test.dart';

import 'support/test_support.dart';
import 'support/web_support.dart';

const _attack = '"><script>alert(\'xss\')</script><b a=\'';
const _escaped =
    '&quot;&gt;&lt;script&gt;alert(&#39;xss&#39;)&lt;&#47;script&gt;'
    '&lt;b a=&#39;';
const _wrong = 'Wrong-Pass-Zeta-Kappa';

void main() {
  late WebHarness web;

  setUp(() async {
    LogCapture();
    web = await WebHarness.start();
  });

  void expectLoginEscaped(WebPage page) {
    expect(page.html, contains('value="$_escaped" required'));
    expect(page.html, isNot(contains('<script')));
    expect(page.html, isNot(contains('"><')));
    expect(page.html, isNot(contains('<b a=')));
    expect(
      RegExp(
        '<input id="login" name="login" type="text" value="[^"]*" '
        'required ',
      ).allMatches(page.html),
      hasLength(1),
    );
  }

  test('логин с разметкой возвращается в поле экранированным: неверный '
      'пароль → 401-страница без чужого <script>', () async {
    final page = await web.deleteByForm(_attack, _wrong);

    expect(page.status, 401, reason: '$page');
    expect(page.html, contains('role="alert">Неверный логин или пароль.</p>'));
    expectLoginEscaped(page);
  });

  test('логин с разметкой и пустой пароль → 400-страница, логин в поле '
      'экранирован', () async {
    final page = await web.postForm(
      '/delete-account',
      fields: {'login': _attack},
    );

    expect(page.status, 400, reason: '$page');
    expect(page.html, contains('role="alert">Введи логин и пароль.</p>'));
    expectLoginEscaped(page);
  });
}
