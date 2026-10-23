import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import '../../data/api/api_exception.dart';
import '../../data/api/auth_api.dart';
import '../../data/session/session_providers.dart';
import '../auth/recovery_code_state.dart';

final _log = Logger('profile');

sealed class ReissueOutcome {
  const ReissueOutcome();
}

final class ReissueDone extends ReissueOutcome {
  const ReissueDone(this.requestId);

  final String requestId;
}

final class ReissueFailed extends ReissueOutcome {
  const ReissueFailed(this.error);

  final ApiException error;

  ApiErrorCode? get code => switch (error) {
    ApiErrorResponse(:final code) => code,
    _ => null,
  };
}

class RecoveryCodeReissue {
  RecoveryCodeReissue(this._ref);

  final Ref _ref;

  Future<ReissueOutcome> reissue({required String password}) async {
    final sw = Stopwatch()..start();
    final userId = _ref.read(sessionProvider).userId ?? '-';
    _log.fine('recovery code reissue request userId=$userId');
    final ReissuedRecoveryCode result;
    try {
      result = await _ref
          .read(authApiProvider)
          .reissueRecoveryCode(password: password);
    } on ApiException catch (e, st) {
      final ms = sw.elapsedMilliseconds;
      switch (e) {
        case ApiErrorResponse(:final statusCode, :final error, :final code):
          _log.info(
            'recovery code reissue rejected code=${error.code} '
            'status=$statusCode userId=$userId rid=${e.requestId} in ${ms}ms '
            '→ ${code == ApiErrorCode.badCredentials ? 'wrong password, error under the field' : 'snackbar'}, '
            'old code still works',
          );
        default:
          _log.warning(
            'recovery code reissue failed ${e.runtimeType}: ${e.details} '
            'userId=$userId rid=${e.requestId} in ${ms}ms → snackbar, '
            'old code still works unless the server already replaced it',
            e,
            st,
          );
      }
      return ReissueFailed(e);
    }
    _ref
        .read(pendingRecoveryCodeProvider.notifier)
        .show(result.recoveryCode, RecoveryCodeReason.reissue);
    _log.info(
      'recovery code reissued userId=$userId rid=${result.requestId} '
      'in ${sw.elapsedMilliseconds}ms → code screen, the old code no longer '
      'works',
    );
    return ReissueDone(result.requestId);
  }
}

final recoveryCodeReissueProvider = Provider<RecoveryCodeReissue>(
  RecoveryCodeReissue.new,
  name: 'recoveryCodeReissue',
);
