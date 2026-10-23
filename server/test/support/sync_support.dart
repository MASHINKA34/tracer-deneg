import 'package:shared/shared.dart';

import 'auth_support.dart';
import 'shared_budget_support.dart';

Future<ApiResponse> pullRaw(
  AuthHarness api,
  TestUser user, {
  String query = '',
}) => api.send(
  'GET',
  '/sync/pull${query.isEmpty ? '' : '?$query'}',
  bearer: user.accessToken,
);

Future<SyncPullResponse> pullAs(
  AuthHarness api,
  TestUser user, {
  int cursor = 0,
  int? limit,
}) async {
  final response = await pullRaw(
    api,
    user,
    query: 'cursor=$cursor${limit == null ? '' : '&limit=$limit'}',
  );
  if (response.status != 200) {
    throw StateError('pull for ${user.login} failed: $response');
  }
  return SyncPullResponse.fromJson(response.json);
}

class PulledPages {
  PulledPages(this.pages);

  final List<SyncPullResponse> pages;

  int get cursor => pages.last.cursor;

  List<T> all<T>(List<T> Function(SyncPullResponse page) select) => [
    for (final page in pages) ...select(page),
  ];
}

Future<PulledPages> pullUntilDone(
  AuthHarness api,
  TestUser user, {
  int cursor = 0,
  int? limit,
  int maxPages = 100,
}) async {
  final pages = <SyncPullResponse>[];
  var next = cursor;
  while (true) {
    final page = await pullAs(api, user, cursor: next, limit: limit);
    pages.add(page);
    if (!page.hasMore) return PulledPages(pages);
    if (page.cursor <= next) {
      throw StateError('pull cursor did not advance: $next → ${page.cursor}');
    }
    if (pages.length >= maxPages) {
      throw StateError('pull did not finish in $maxPages pages');
    }
    next = page.cursor;
  }
}
