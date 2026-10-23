import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'api_config.dart';
import 'token_store.dart';

final apiConfigProvider = Provider<ApiConfig>(
  (ref) => ApiConfig.resolve(),
  name: 'apiConfig',
);

final tokenStoreProvider = Provider<TokenStore>(
  (ref) => MemoryTokenStore(),
  name: 'tokenStore',
);

final apiClientProvider = Provider<ApiClient>((ref) {
  final client = ApiClient(
    config: ref.watch(apiConfigProvider),
    tokens: ref.watch(tokenStoreProvider),
  );
  ref.onDispose(client.close);
  return client;
}, name: 'apiClient');
