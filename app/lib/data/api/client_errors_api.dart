import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import 'api_client.dart';
import 'api_exception.dart';
import 'api_providers.dart';

final _log = Logger('errors');

const String clientErrorsPath = '/client-errors';

final class ClientErrorSent {
  const ClientErrorSent({required this.id, required this.requestId});

  final String id;
  final String requestId;
}

class ClientErrorsApi {
  ClientErrorsApi(this._client);

  final ApiClient _client;

  Future<ClientErrorSent> send(
    ClientErrorReport report, {
    required bool withSession,
  }) async {
    if (withSession) {
      try {
        return await _post(report, auth: true);
      } on ApiSessionExpired catch (e) {
        _log.info(
          'POST $clientErrorsPath kind=${report.kind.code} not sent with '
          'session: ${e.details} rid=${e.requestId} → sending anonymously',
        );
      }
    }
    return _post(report, auth: false);
  }

  Future<ClientErrorSent> _post(
    ClientErrorReport report, {
    required bool auth,
  }) async {
    final response = await _client.post(
      clientErrorsPath,
      body: report.toJson(),
      auth: auth,
    );
    final data = response.data;
    final id = data is Map<String, Object?> && data['id'] is String
        ? data['id']! as String
        : '-';
    if (id == '-') {
      _log.fine(
        'POST $clientErrorsPath ${response.statusCode} without report id '
        'rid=${response.requestId}',
      );
    }
    return ClientErrorSent(id: id, requestId: response.requestId);
  }
}

final clientErrorsApiProvider = Provider<ClientErrorsApi>(
  (ref) => ClientErrorsApi(ref.watch(apiClientProvider)),
  name: 'clientErrorsApi',
);
