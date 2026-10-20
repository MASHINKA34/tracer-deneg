import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:shared/logging.dart';

import '../../data/db/redact_db_error.dart';

final _log = Logger('providers');

final class ProviderLogger extends ProviderObserver {
  const ProviderLogger();

  @override
  void didAddProvider(ProviderObserverContext context, Object? value) {
    _log.fine('provider added ${context.provider}');
  }

  @override
  void didDisposeProvider(ProviderObserverContext context) {
    _log.fine('provider disposed ${context.provider}');
  }

  @override
  void providerDidFail(
    ProviderObserverContext context,
    Object error,
    StackTrace stackTrace,
  ) {
    final redacted = redactDbError(error);
    _log.warning(
      'provider ${context.provider} failed, exposed as error state: '
      '${describeError(redacted)}',
      redacted,
      stackTrace,
    );
  }
}
