import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

final _log = Logger('auth');

enum RecoveryCodeReason { register, recover, reissue }

final class PendingRecoveryCode {
  const PendingRecoveryCode({required this.code, required this.reason});

  final String code;
  final RecoveryCodeReason reason;

  @override
  String toString() =>
      'PendingRecoveryCode(${reason.name}, ${maskRecoveryCode(code)})';
}

final pendingRecoveryCodeProvider =
    NotifierProvider<PendingRecoveryCodeController, PendingRecoveryCode?>(
      PendingRecoveryCodeController.new,
      name: 'pendingRecoveryCode',
    );

final class PendingRecoveryCodeController
    extends Notifier<PendingRecoveryCode?> {
  @override
  PendingRecoveryCode? build() => null;

  void show(String code, RecoveryCodeReason reason) {
    final replaced = state;
    state = PendingRecoveryCode(code: formatRecoveryCode(code), reason: reason);
    _log.info(
      'recovery code kept in memory until confirmed reason=${reason.name}'
      '${replaced == null ? '' : ' (replaces unconfirmed ${replaced.reason.name} code)'}',
    );
  }

  void confirm() {
    final current = state;
    if (current == null) {
      _log.fine('recovery code confirm ignored: nothing is pending');
      return;
    }
    state = null;
    _log.info(
      'recovery code confirmed as saved reason=${current.reason.name} → '
      'dropped from memory',
    );
  }
}
