import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'api_config.dart';

final apiConfigProvider = Provider<ApiConfig>(
  (ref) => ApiConfig.resolve(),
  name: 'apiConfig',
);

final apiClientProvider = Provider<ApiClient>((ref) {
  final client = ApiClient(config: ref.watch(apiConfigProvider));
  ref.onDispose(client.close);
  return client;
}, name: 'apiClient');
