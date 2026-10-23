import 'package:logging/logging.dart';
import 'package:shared/logging.dart';

final _log = Logger('api');

final class AuthTokens {
  const AuthTokens({required this.accessToken, required this.refreshToken});

  final String accessToken;
  final String refreshToken;

  @override
  String toString() =>
      'AuthTokens(access=${maskToken(accessToken)}, '
      'refresh=${maskToken(refreshToken)})';
}

abstract interface class TokenStore {
  Future<AuthTokens?> readTokens();

  Future<void> saveTokens(AuthTokens tokens);
}

final class MemoryTokenStore implements TokenStore {
  MemoryTokenStore([this._tokens]);

  AuthTokens? _tokens;

  @override
  Future<AuthTokens?> readTokens() async => _tokens;

  @override
  Future<void> saveTokens(AuthTokens tokens) async {
    _log.fine('tokens saved in memory store $tokens');
    _tokens = tokens;
  }
}
