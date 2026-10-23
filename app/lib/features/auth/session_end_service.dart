import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import '../../data/api/api_exception.dart';
import '../../data/db/redact_db_error.dart';
import '../../data/providers.dart';
import '../../data/session/session_state.dart';

final _log = Logger('auth');

class SessionEndService {
  SessionEndService(this._ref);

  final Ref _ref;

  Future<void> reportEnded(SessionEnded ended) async {
    final sw = Stopwatch()..start();
    final what = switch (ended.reason) {
      SessionEndReason.refreshRejected => 'refresh token rejected',
      SessionEndReason.sessionRejected => 'session rejected by server',
      SessionEndReason.noSession ||
      SessionEndReason.endedEarlier => 'session ended',
    };
    final String queue;
    try {
      queue = '${await _ref.read(outboxQueueProvider).count()}';
    } catch (e, st) {
      final error = redactDbError(e);
      _log.warning(
        '$what → re-login reason=${ended.reason.name} '
        'userId=${ended.user.userId}: queue size not read after '
        '${sw.elapsedMilliseconds}ms, local data kept anyway: '
        '${describeError(error)}',
        error,
        st,
      );
      return;
    }
    _log.info(
      '$what → re-login reason=${ended.reason.name} '
      'userId=${ended.user.userId} queue=$queue → sign-in screen with '
      '"session ended" notice, local data and queue kept '
      '(counted in ${sw.elapsedMilliseconds}ms)',
    );
  }
}

final sessionEndServiceProvider = Provider<SessionEndService>(
  SessionEndService.new,
  name: 'sessionEndService',
);
