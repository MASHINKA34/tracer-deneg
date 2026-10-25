import 'package:server/web/web_page.dart';
import 'package:test/test.dart';

import 'support/test_support.dart';
import 'support/web_support.dart';

const _withContact =
    'Нет ни пароля, ни кода восстановления? Напиши на privacy@example.test '
    'и укажи логин. Удалим аккаунт вручную в течение 30 дней. Можем задать '
    'пару вопросов об аккаунте, чтобы убедиться, что он твой.';

const _withoutContact =
    'Нет ни пароля, ни кода восстановления? Напиши оператору данных '
    '(контакт: не указан) и укажи логин. Удалим аккаунт вручную в течение '
    '30 дней. Можем задать пару вопросов об аккаунте, чтобы убедиться, что он '
    'твой.';

void main() {
  late LogCapture logs;

  setUp(() => logs = LogCapture());

  group('удаление без пароля и кода восстановления — через контакт', () {
    test('/delete-account: под формой контакт, логин и срок 30 дней', () async {
      final web = await WebHarness.start(
        privacy: const PrivacySettings(contact: 'privacy@example.test'),
      );

      final page = await web.get('/delete-account');

      expect(page.status, 200);
      expect(page.text, contains(_withContact));
      expect(page.text, contains('Не помнишь пароль? Восстанови его'));
    });

    test('/delete-account: контакт пуст → «оператору данных (контакт: не '
        'указан)»', () async {
      final web = await WebHarness.start();

      final page = await web.get('/delete-account');

      expect(page.text, contains(_withoutContact));
      expect(page.text, isNot(contains('Напиши на не указан')));
    });

    test('/delete-account: контакт экранирован, текст остаётся и на странице '
        'с ошибкой', () async {
      final web = await WebHarness.start(
        privacy: const PrivacySettings(contact: '<b>op</b> & t.me/Op'),
      );

      final form = await web.get('/delete-account');
      final failed = await web.postForm(
        '/delete-account',
        fields: {'login': 'nobody', 'password': 'Wrong-Pass-Zeta-Kappa'},
      );

      for (final page in [form, failed]) {
        expect(
          page.html,
          contains('Напиши на &lt;b&gt;op&lt;&#47;b&gt; &amp; t.me&#47;Op'),
        );
        expect(page.html, isNot(contains('<b>op</b>')));
      }
      expect(failed.status, 401);
    });

    test(
      '/privacy: тот же текст в разделе «Как удалить аккаунт и данные»',
      () async {
        final filled = await WebHarness.start(
          privacy: const PrivacySettings(contact: 'privacy@example.test'),
        );
        final empty = await WebHarness.start();

        final withContact = (await filled.get('/privacy')).text;
        final withoutContact = (await empty.get('/privacy')).text;

        expect(withContact, contains(_withContact));
        expect(
          withContact.indexOf(_withContact),
          greaterThan(withContact.indexOf('Как удалить аккаунт и данные')),
        );
        expect(withoutContact, contains(_withoutContact));
      },
    );

    test('в debug-строке показа /delete-account — задан ли контакт, без '
        'самого контакта', () async {
      final web = await WebHarness.start(
        privacy: const PrivacySettings(contact: 'Contact-Value-Lambda'),
      );
      logs.clear();

      await web.get('/delete-account');

      expect(
        logs.lines,
        contains(
          matches(
            r'DEBUG \[web\] page shown /delete-account status=200 '
            r'contact=set bytes=\d+',
          ),
        ),
      );
      expect(logs.text, isNot(contains('Contact-Value-Lambda')));
    });
  });
}
