import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../session/session_providers.dart';
import 'api_client.dart';
import 'api_config.dart';
import 'token_store.dart';

final apiConfigProvider = Provider<ApiConfig>(
  (ref) => ApiConfig.resolve(),
  name: 'apiConfig',
);

final tokenStoreProvider = Provider<TokenStore>(
  (ref) => ref.watch(sessionStoreProvider),
  name: 'tokenStore',
);

final apiClientProvider = Provider<ApiClient>((ref) {
  final client = ApiClient(
    config: ref.watch(apiConfigProvider),
    tokens: ref.watch(tokenStoreProvider),
  );
  listenSessionExpired(ref, client);
  ref.onDispose(client.close);
  return client;
}, name: 'apiClient');

void listenSessionExpired(Ref ref, ApiClient client) {
  final ended = client.sessionExpired.listen(
    (event) => ref.read(sessionProvider.notifier).ended(event.reason),
  );
  ref.onDispose(ended.cancel);
}
