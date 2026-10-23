import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../api/api_exception.dart';
import 'secure_values.dart';
import 'session.dart';
import 'session_state.dart';
import 'session_store.dart';

final _log = Logger('session');

final secureValuesProvider = Provider<SecureValues>(
  (ref) => const FlutterSecureValues(),
  name: 'secureValues',
);

final sessionStoreProvider = Provider<SessionStore>(
  (ref) => SessionStore(ref.watch(secureValuesProvider)),
  name: 'sessionStore',
);

final sessionProvider = NotifierProvider<SessionController, SessionState>(
  SessionController.new,
  name: 'session',
);

final class SessionController extends Notifier<SessionState> {
  @override
  SessionState build() => const SessionAbsent();

  Future<void> save(Session session) async {
    final userId = session.user.userId;
    await ref.read(sessionStoreProvider).save(session);
    if (!ref.mounted) {
      _log.warning(
        'session saved userId=$userId, but the app scope is gone: '
        'applies after restart',
      );
      return;
    }
    final previous = state;
    state = SessionActive(session.user);
    _log.info('session state ${previous.name} → active userId=$userId');
  }

  Future<void> clear() async {
    await ref.read(sessionStoreProvider).clear();
    if (!ref.mounted) {
      _log.warning('session cleared, but the app scope is gone');
      return;
    }
    final previous = state;
    state = const SessionAbsent();
    _log.info('session state ${previous.name} → absent');
  }

  void ended(SessionEndReason reason) {
    if (!ref.mounted) {
      _log.fine('session end reason=${reason.name} after app scope is gone');
      return;
    }
    final current = state;
    if (current is! SessionActive) {
      _log.fine(
        'session end reason=${reason.name} ignored: state is ${current.name}',
      );
      return;
    }
    state = SessionEnded(current.user, reason);
    _log.info(
      'session state active → ended reason=${reason.name} '
      'userId=${current.user.userId}',
    );
  }
}
