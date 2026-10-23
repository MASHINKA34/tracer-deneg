import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../data/session/session_state.dart';
import 'router.dart';

final _log = Logger('auth');

final signInRequiredProvider = Provider<bool>(
  (ref) => false,
  name: 'signInRequired',
);

final class AuthGate {
  const AuthGate({
    required this.session,
    required this.changes,
    required this.signInRequired,
  });

  final SessionState Function() session;
  final Listenable changes;
  final bool signInRequired;

  String? redirect(Uri uri) => authRedirect(
    uri: uri,
    session: session(),
    signInRequired: signInRequired,
  );
}

String? authRedirect({
  required Uri uri,
  required SessionState session,
  required bool signInRequired,
}) {
  final path = uri.path;
  final inAuthStack = AppRoutes.isAuthStack(path);
  switch (session) {
    case SessionActive(:final user):
      if (!inAuthStack) return null;
      _log.fine(
        'auth stack: session active userId=${user.userId} → leaving $path '
        'for ${AppRoutes.month}',
      );
      return AppRoutes.month;
    case SessionAbsent() || SessionEnded():
      if (inAuthStack || !signInRequired) return null;
      _log.fine(
        'auth stack: session ${session.name} → ${_place(uri)} needs sign-in '
        '→ ${AppRoutes.login}',
      );
      return AppRoutes.login;
  }
}

String _place(Uri uri) {
  if (!uri.hasScheme) return uri.path;
  final path = uri.path == '/' ? '' : uri.path;
  return '${uri.scheme}://${uri.host}$path';
}
