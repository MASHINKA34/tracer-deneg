import 'dart:convert';
import 'dart:typed_data';

import 'package:logging/logging.dart';
import 'package:shared/shared.dart';
import 'package:shelf/shelf.dart';

import '../account/account_service.dart';
import '../auth/auth_service.dart';
import '../limits/request_limits.dart';
import '../limits/sliding_window.dart';
import '../limits/trusted_proxies.dart';
import 'web_page.dart';

final _log = Logger('web');

const String _formContentType = 'application/x-www-form-urlencoded';
const Map<String, String> _noStore = {'cache-control': 'no-store'};

Handler deleteAccountFormHandler() {
  final html = renderDeleteAccountForm();
  return (Request request) {
    _log.fine('page shown $deleteAccountPath status=200 bytes=${html.length}');
    return htmlResponse(200, html, headers: _noStore);
  };
}

Handler deleteAccountSubmitHandler({
  required AccountService account,
  required RequestLimits limits,
}) => (Request request) async {
  final sw = Stopwatch()..start();
  final ip = clientIp(request, limits.trustedProxies);

  final ipLimiter = limits.authRequests;
  final ipWait = ipLimiter.blockedFor(ip);
  if (ipWait != null) {
    final seconds = retryAfterSeconds(ipWait);
    _log.warning(
      'delete-account form blocked: ip rate limit hit '
      'limiter=${ipLimiter.name} ip=$ip '
      'limit=${ipLimiter.limit}/${ipLimiter.window.inSeconds}s '
      'retryAfter=${seconds}s',
    );
    return _tooMany(seconds, 'Слишком много запросов.');
  }
  ipLimiter.record(ip);

  final form = await _readForm(request);
  if (form.problem != null) {
    _log.warning(
      'delete-account form rejected reason=${ApiErrorCode.badRequest.code} '
      'problem="${form.problem}" ip=$ip in ${sw.elapsedMilliseconds}ms',
    );
    return htmlResponse(
      400,
      renderDeleteAccountForm(
        error:
            'Не получилось прочитать форму. Открой страницу удаления '
            'аккаунта заново и отправь форму ещё раз.',
      ),
      headers: _noStore,
    );
  }

  final login = form.fields['login'] ?? '';
  final password = form.fields['password'] ?? '';
  final missing = [
    if (login.trim().isEmpty) 'login',
    if (password.isEmpty) 'password',
  ];
  if (missing.isNotEmpty) {
    _log.warning(
      'delete-account form rejected reason=${ApiErrorCode.badRequest.code} '
      'missing=${missing.join(',')} ip=$ip in ${sw.elapsedMilliseconds}ms',
    );
    return htmlResponse(
      400,
      renderDeleteAccountForm(error: 'Введи логин и пароль.', login: login),
      headers: _noStore,
    );
  }

  final key = normalizeLogin(login);
  final masked = maskLogin(key);
  final failures = limits.loginFailures;
  final invalid = validateLogin(key);
  if (invalid != null) {
    _log.fine(
      'delete-account attempts not tracked: login format invalid '
      'reason=${invalid.code}',
    );
  } else {
    final wait = failures.blockedFor(key);
    if (wait != null) {
      final seconds = retryAfterSeconds(wait);
      _log.warning(
        'delete-account form blocked: login attempts limit hit '
        'login=$masked failures=${failures.count(key)}/$loginFailureLimit '
        'window=${loginFailureWindow.inMinutes}m retryAfter=${seconds}s '
        'ip=$ip',
      );
      return _tooMany(seconds, 'Слишком много неудачных попыток.');
    }
  }
  final attempt = invalid == null ? failures.record(key) : null;

  try {
    final deletion = await account.deleteAccountByLogin(
      login: login,
      password: password,
    );
    if (attempt != null) failures.reset(key);
    _log.info(
      'delete-account form: account deleted login=$masked ip=$ip '
      'budgetsDeleted='
      '${deletion.personalBudgetsDeleted + deletion.sharedBudgetsDeleted} '
      'budgetsTransferred=${deletion.sharedBudgetsTransferred} '
      'budgetsLeft=${deletion.sharedBudgetsLeft} '
      'sessionsRevoked=${deletion.sessionsRevoked} '
      'in ${sw.elapsedMilliseconds}ms',
    );
    return htmlResponse(200, renderAccountDeleted(), headers: _noStore);
  } on AuthFailure catch (e) {
    if (e.reason == AuthFailureReason.badCredentials) {
      final count = attempt == null ? null : failures.count(key);
      if (count != null && count >= loginFailureLimit) {
        _log.warning(
          'delete-account login attempts exhausted login=$masked '
          'failures=$count/$loginFailureLimit '
          'window=${loginFailureWindow.inMinutes}m → next attempts blocked '
          'for ${retryAfterSeconds(failures.blockedFor(key)!)}s',
        );
      }
      _log.warning(
        'delete-account form rejected reason=${e.reason.code} login=$masked '
        'failures=${count == null ? 'untracked' : '$count/$loginFailureLimit'} '
        'ip=$ip in ${sw.elapsedMilliseconds}ms',
      );
      return htmlResponse(
        401,
        renderDeleteAccountForm(
          error: 'Неверный логин или пароль.',
          login: login,
        ),
        headers: _noStore,
      );
    }
    if (attempt != null) failures.forget(key, attempt);
    _log.warning(
      'delete-account form rejected reason=${e.reason.code} login=$masked '
      'ip=$ip in ${sw.elapsedMilliseconds}ms',
    );
    return htmlResponse(410, renderAlreadyDeleted(), headers: _noStore);
  } catch (e) {
    if (attempt != null) failures.forget(key, attempt);
    _log.fine(
      'delete-account attempt not counted: ${e.runtimeType} login=$masked',
    );
    rethrow;
  }
};

String renderDeleteAccountForm({
  String? error,
  String login = '',
}) => renderPage(
  title: 'Удаление аккаунта',
  body:
      '<h1>Удаление аккаунта</h1>\n'
      '<p>Здесь можно удалить аккаунт «Милиончика» без приложения. '
      'Удаление необратимо.</p>\n'
      '<ul>\n'
      '<li>Личный бюджет со всеми тратами удаляется сразу.</li>\n'
      '<li>Имя, дата рождения, пароль и код восстановления стираются, '
      'все входы на устройствах завершаются.</li>\n'
      '<li>Из общих бюджетов ты выходишь, твои траты в них остаются с '
      'автором «Удалённый участник».</li>\n'
      '</ul>\n'
      '<p class="muted">Подробнее в '
      '<a href="$privacyPath">политике конфиденциальности</a>.</p>\n'
      '${error == null ? '' : '<p class="alert" role="alert">${escapeHtml(error)}</p>\n'}'
      '<form class="card" method="post" action="$deleteAccountPath">\n'
      '<label for="login">Логин</label>\n'
      '<input id="login" name="login" type="text" '
      'value="${escapeHtml(login)}" required '
      'maxlength="$loginMaxLength" autocomplete="username" '
      'autocapitalize="none" spellcheck="false">\n'
      '<label for="password">Пароль</label>\n'
      '<input id="password" name="password" type="password" required '
      'maxlength="$passwordMaxLength" autocomplete="current-password">\n'
      '<button type="submit">Удалить аккаунт навсегда</button>\n'
      '</form>\n'
      '<p class="muted">Не помнишь пароль? Восстанови его в приложении: '
      '«Забыл пароль?» на экране входа и код восстановления.</p>\n',
);

String renderAccountDeleted() => renderPage(
  title: 'Аккаунт удалён',
  body:
      '<h1>Аккаунт удалён</h1>\n'
      '<p class="alert done" role="status">Аккаунт и личные данные '
      'удалены.</p>\n'
      '<p>Личный бюджет удалён, все входы на устройствах завершены. '
      'Приложение на телефоне попросит войти снова. Чтобы стереть копию '
      'данных с телефона, выйди из аккаунта в приложении или удали '
      'приложение.</p>\n'
      '<p class="muted"><a href="$privacyPath">Политика '
      'конфиденциальности</a></p>\n',
);

String renderAlreadyDeleted() => renderPage(
  title: 'Аккаунт уже удалён',
  body:
      '<h1>Аккаунт уже удалён</h1>\n'
      '<p>Этот аккаунт был удалён раньше, повторно удалять нечего.</p>\n'
      '<p class="muted"><a href="$privacyPath">Политика '
      'конфиденциальности</a></p>\n',
);

String renderTooManyAttempts(String reason, int seconds) => renderPage(
  title: 'Слишком много попыток',
  body:
      '<h1>Слишком много попыток</h1>\n'
      '<p class="alert" role="alert">${escapeHtml(reason)} Попробуй через '
      '${escapeHtml(retryWaitText(seconds))}.</p>\n'
      '<p>Это защита от подбора пароля. Аккаунт не удалён.</p>\n'
      '<p><a href="$deleteAccountPath">Вернуться к форме</a></p>\n',
);

Response _tooMany(int seconds, String reason) => htmlResponse(
  429,
  renderTooManyAttempts(reason, seconds),
  headers: {..._noStore, 'retry-after': '$seconds'},
);

class _Form {
  const _Form.ok(this.fields) : problem = null;
  const _Form.failed(this.problem) : fields = const {};

  final Map<String, String> fields;
  final String? problem;
}

Future<_Form> _readForm(Request request) async {
  final mimeType = request.mimeType;
  final bytes = await _collect(request.read());
  if (mimeType != _formContentType) {
    return _Form.failed(
      'content-type is ${mimeType ?? 'missing'}, not $_formContentType '
      '(${bytes.length} bytes)',
    );
  }
  final String text;
  try {
    text = utf8.decode(bytes);
  } on FormatException catch (e) {
    return _Form.failed(
      'body is not UTF-8: ${e.message} (${bytes.length} bytes)',
    );
  }
  try {
    return _Form.ok(Uri.splitQueryString(text));
  } on ArgumentError catch (e) {
    return _Form.failed(
      'form encoding invalid: ${e.message} (${bytes.length} bytes)',
    );
  } on FormatException catch (e) {
    return _Form.failed(
      'form encoding invalid: ${e.message} (${bytes.length} bytes)',
    );
  }
}

Future<List<int>> _collect(Stream<List<int>> stream) async {
  final builder = BytesBuilder(copy: false);
  await for (final chunk in stream) {
    builder.add(chunk);
  }
  return builder.takeBytes();
}
