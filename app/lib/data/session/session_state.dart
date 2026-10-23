import '../api/api_exception.dart';
import 'session.dart';

sealed class SessionState {
  const SessionState();

  SessionUser? get user;

  String? get userId => user?.userId;

  String get name;
}

final class SessionActive extends SessionState {
  const SessionActive(this.user);

  @override
  final SessionUser user;

  @override
  String get name => 'active';

  @override
  String toString() => 'SessionActive($user)';
}

final class SessionAbsent extends SessionState {
  const SessionAbsent();

  @override
  SessionUser? get user => null;

  @override
  String get name => 'absent';

  @override
  String toString() => 'SessionAbsent()';
}

final class SessionEnded extends SessionState {
  const SessionEnded(this.user, this.reason);

  @override
  final SessionUser user;

  final SessionEndReason reason;

  @override
  String get name => 'ended';

  @override
  String toString() => 'SessionEnded(${reason.name}, $user)';
}
