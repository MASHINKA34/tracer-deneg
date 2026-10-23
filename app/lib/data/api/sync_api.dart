import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import 'api_client.dart';
import 'api_exception.dart';
import 'api_providers.dart';

final _log = Logger('sync');

const String pullPath = '/sync/pull';

final class PullPage {
  const PullPage({required this.response, required this.requestId});

  final SyncPullResponse response;
  final String requestId;

  @override
  String toString() => 'PullPage($response rid=$requestId)';
}

class SyncApi {
  SyncApi(this._client);

  final ApiClient _client;

  Future<PullPage> pull(SyncPullQuery query) async {
    final response = await _client.get(
      pullPath,
      query: query.toQueryParameters(),
    );
    try {
      return PullPage(
        response: SyncPullResponse.fromJson(response.data),
        requestId: response.requestId,
      );
    } on FormatException catch (e) {
      _log.warning(
        'GET $pullPath ${response.statusCode} cursor=${query.cursor} answered '
        'without a pull page → bad response: ${e.message} '
        'rid=${response.requestId}',
      );
      throw ApiBadResponse(
        method: 'GET',
        path: '${_client.config.baseUrl.path}$pullPath',
        requestId: response.requestId,
        statusCode: response.statusCode,
        reason: 'pull: ${e.message}',
      );
    }
  }
}

final syncApiProvider = Provider<SyncApi>(
  (ref) => SyncApi(ref.watch(apiClientProvider)),
  name: 'syncApi',
);
