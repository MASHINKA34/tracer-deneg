import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import 'api_client.dart';
import 'api_exception.dart';
import 'api_providers.dart';

final _log = Logger('account');

const String mePath = '/me';

final class MeReply {
  const MeReply({
    required this.user,
    required this.statusCode,
    required this.requestId,
  });

  final User user;
  final int statusCode;
  final String requestId;

  @override
  String toString() => 'MeReply($user status=$statusCode rid=$requestId)';
}

class AccountApi {
  AccountApi(this._client);

  final ApiClient _client;

  Future<MeReply> me() async {
    final response = await _client.get(mePath);
    try {
      return MeReply(
        user: User.fromJson(response.data),
        statusCode: response.statusCode,
        requestId: response.requestId,
      );
    } on FormatException catch (e) {
      final reason = withoutBirthdayValues(e.message);
      _log.warning(
        'GET $mePath ${response.statusCode} answered without a user → bad '
        'response: $reason rid=${response.requestId}',
      );
      throw ApiBadResponse(
        method: 'GET',
        path: '${_client.config.baseUrl.path}$mePath',
        requestId: response.requestId,
        statusCode: response.statusCode,
        reason: 'me: $reason',
      );
    }
  }
}

String withoutBirthdayValues(String message) =>
    message.startsWith('Birthday needs') ||
        message.startsWith('Invalid birthday')
    ? 'birthdayMonth/birthdayDay: not a valid month and day (values not logged)'
    : message;

final accountApiProvider = Provider<AccountApi>(
  (ref) => AccountApi(ref.watch(apiClientProvider)),
  name: 'accountApi',
);
