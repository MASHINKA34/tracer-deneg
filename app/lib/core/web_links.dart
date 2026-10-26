import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/api/api_providers.dart';

final _log = Logger('links');

enum WebPage {
  privacy('/privacy'),
  deleteAccount('/delete-account');

  const WebPage(this.path);

  final String path;
}

enum WebLinkSource { profile, register, deleteAccount }

Uri webPageUrl(Uri apiBaseUrl, WebPage page) => Uri(
  scheme: apiBaseUrl.scheme,
  host: apiBaseUrl.host,
  port: apiBaseUrl.hasPort ? apiBaseUrl.port : null,
  path: page.path,
);

typedef UrlLauncher = Future<bool> Function(Uri url);

Future<bool> launchInExternalBrowser(Uri url) =>
    launchUrl(url, mode: LaunchMode.externalApplication);

final urlLauncherProvider = Provider<UrlLauncher>(
  (ref) => launchInExternalBrowser,
  name: 'urlLauncher',
);

final class WebLinks {
  WebLinks(this._ref);

  final Ref _ref;

  Future<bool> open(WebPage page, {required WebLinkSource from}) async {
    final sw = Stopwatch()..start();
    final what = 'page=${page.path} from=${from.name}';
    Uri? url;
    try {
      url = webPageUrl(_ref.read(apiConfigProvider).baseUrl, page);
      _log.fine('link open $what url=$url → external browser');
      final launched = await _ref.read(urlLauncherProvider)(url);
      if (launched) {
        _log.info(
          'link open $what result=launched in ${sw.elapsedMilliseconds}ms',
        );
        return true;
      }
      _log.warning(
        'link open $what result=failed in ${sw.elapsedMilliseconds}ms: '
        'no app on the phone took url=$url → error snackbar',
      );
      return false;
    } catch (e, st) {
      _log.warning(
        'link open $what result=failed in ${sw.elapsedMilliseconds}ms '
        'url=${url ?? 'not built'}: ${describeError(e)} → error snackbar',
        e,
        st,
      );
      return false;
    }
  }
}

final webLinksProvider = Provider<WebLinks>(WebLinks.new, name: 'webLinks');
