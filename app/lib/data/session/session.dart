import 'package:shared/logging.dart';

import '../api/token_store.dart';

final class SessionUser {
  const SessionUser({
    required this.userId,
    required this.login,
    required this.displayName,
  });

  final String userId;
  final String login;
  final String displayName;

  @override
  bool operator ==(Object other) =>
      other is SessionUser &&
      other.userId == userId &&
      other.login == login &&
      other.displayName == displayName;

  @override
  int get hashCode => Object.hash(userId, login, displayName);

  @override
  String toString() =>
      'SessionUser(userId=$userId, login=${maskLogin(login)}, '
      'displayName=<${displayName.length} chars>)';
}

final class Session {
  const Session({required this.user, required this.tokens});

  final SessionUser user;
  final AuthTokens tokens;

  @override
  String toString() => 'Session($user, $tokens)';
}
