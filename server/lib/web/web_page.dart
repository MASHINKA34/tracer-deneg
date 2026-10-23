import 'dart:convert';

import 'package:cryptography/dart.dart' show DartSha256;
import 'package:logging/logging.dart';
import 'package:shared/logging.dart';
import 'package:shelf/shelf.dart';

import '../limits/request_limits.dart';

final _log = Logger('web');

const String privacyPath = '/privacy';
const String deleteAccountPath = '/delete-account';
const String notSpecified = 'не указан';

class PrivacySettings {
  const PrivacySettings({this.contact, this.operator});

  final String? contact;
  final String? operator;

  Map<String, Object?> toLogContext() => {
    'contact': contact == null ? 'empty' : 'set',
    'operator': operator == null ? 'empty' : 'set',
  };
}

const String pageCss =
    ':root{color-scheme:light dark;--bg:#F6F2EB;--surface:#FFFFFF;'
    '--surface-2:#F0EAE1;--border:#E9E2D7;--border-strong:#D2C7B7;'
    '--text:#1E1A15;--text-2:#6B6257;--accent:#C2541C;--soft:#FBE7D8;'
    '--on-soft:#8A3A10;--danger:#D0453A;--on-danger:#FFFFFF;'
    '--success:#2E8B57}'
    '@media (prefers-color-scheme:dark){:root{--bg:#14120F;'
    '--surface:#1E1B17;--surface-2:#29251F;--border:#322D26;'
    '--border-strong:#4A443B;--text:#F4EFE7;--text-2:#B5AC9F;'
    '--accent:#F0884A;--soft:#3A2418;--on-soft:#F6B48A;--danger:#F07167;'
    '--on-danger:#1E1A15;--success:#5CC48A}}'
    '*{box-sizing:border-box}'
    'html{-webkit-text-size-adjust:100%}'
    'body{margin:0;background:var(--bg);color:var(--text);'
    'font:16px/1.5 system-ui,-apple-system,"Segoe UI",Roboto,sans-serif}'
    'main{max-width:640px;margin:0 auto;padding:24px 16px 48px}'
    '.brand{margin:0 0 20px;color:var(--text-2);font-size:14px;'
    'font-weight:600;letter-spacing:.02em}'
    'h1{font-size:26px;line-height:1.25;margin:0 0 12px}'
    'h2{font-size:19px;line-height:1.3;margin:28px 0 8px}'
    'p{margin:0 0 12px}'
    'ul{margin:0 0 12px;padding-left:22px}'
    'li{margin-bottom:6px}'
    'a{color:var(--accent)}'
    '.card{background:var(--surface);border:1px solid var(--border);'
    'border-radius:16px;padding:20px;margin:16px 0}'
    '.card>:last-child{margin-bottom:0}'
    '.muted{color:var(--text-2);font-size:14px}'
    '.alert{border-radius:12px;padding:12px 16px;margin:16px 0;'
    'background:var(--soft);color:var(--on-soft);font-weight:600}'
    '.alert.done{background:var(--surface-2);color:var(--success)}'
    'label{display:block;font-weight:600;margin:16px 0 6px}'
    'input{display:block;width:100%;min-height:48px;font:inherit;'
    'padding:10px 14px;border:1px solid var(--border-strong);'
    'border-radius:12px;background:var(--surface-2);color:var(--text)}'
    'input:focus{outline:2px solid var(--accent);outline-offset:1px}'
    'button{display:block;width:100%;min-height:48px;margin-top:24px;'
    'padding:10px 16px;font:inherit;font-weight:600;border:0;'
    'border-radius:12px;background:var(--danger);color:var(--on-danger);'
    'cursor:pointer}'
    'button:focus-visible{outline:2px solid var(--text);outline-offset:2px}';

final String pageCssHash =
    'sha256-${base64.encode(const DartSha256().hashSync(utf8.encode(pageCss)).bytes)}';

final String contentSecurityPolicy =
    "default-src 'none'; style-src '$pageCssHash'; form-action 'self'; "
    "frame-ancestors 'none'; base-uri 'none'";

Map<String, String> get webSecurityHeaders => {
  'content-security-policy': contentSecurityPolicy,
  'x-content-type-options': 'nosniff',
  'x-frame-options': 'DENY',
  'referrer-policy': 'no-referrer',
};

const _escape = HtmlEscape();

String escapeHtml(String text) => _escape.convert(text);

String renderPage({required String title, required String body}) =>
    '<!doctype html>\n'
    '<html lang="ru">\n'
    '<head>\n'
    '<meta charset="utf-8">\n'
    '<meta name="viewport" content="width=device-width, initial-scale=1">\n'
    '<meta name="color-scheme" content="light dark">\n'
    '<title>${escapeHtml(title)} · Милиончик</title>\n'
    '<style>$pageCss</style>\n'
    '</head>\n'
    '<body>\n'
    '<main>\n'
    '<p class="brand">Милиончик</p>\n'
    '$body'
    '</main>\n'
    '</body>\n'
    '</html>\n';

Response htmlResponse(
  int status,
  String html, {
  Map<String, String> headers = const {},
}) => Response(
  status,
  body: html,
  headers: {
    'content-type': 'text/html; charset=utf-8',
    ...webSecurityHeaders,
    ...headers,
  },
);

Middleware webErrorPages() =>
    (inner) => (request) async {
      try {
        return await inner(request);
      } on HijackException {
        rethrow;
      } on RequestBodyTooLarge catch (e) {
        _log.fine(
          'web page body over limit ${request.method} '
          '${request.requestedUri.path} read=${e.received} '
          '→ passed to body size limit',
        );
        rethrow;
      } catch (e, st) {
        final rid = currentRequestId();
        _log.severe(
          'web page failed ${request.method} ${request.requestedUri.path} '
          '→ 500 page: ${describeError(e)}',
          e,
          st,
        );
        return htmlResponse(
          500,
          renderPage(
            title: 'Ошибка сервера',
            body:
                '<h1>Что-то пошло не так</h1>\n'
                '<p>Сервер не смог выполнить запрос. Попробуй ещё раз '
                'через несколько минут.</p>\n'
                '${rid == null ? '' : '<p class="muted">Код запроса: ${escapeHtml(rid)}</p>\n'}',
          ),
          headers: {'cache-control': 'no-store'},
        );
      }
    };
