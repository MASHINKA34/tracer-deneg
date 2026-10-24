import 'package:shared/logging.dart';

final RegExp _bearer = RegExp(r'(Bearer\s+)([A-Za-z0-9._~+/=-]{8,})');

final RegExp _jwt = RegExp(
  r'eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}',
);

final RegExp _secretField = RegExp(
  r'("(?:password|newPassword|accessToken|refreshToken|token|recoveryCode)"'
  r'\s*:\s*")([^"]*)(")',
);

final RegExp _refreshToken = RegExp(
  r'(?<![A-Za-z0-9_-])[A-Za-z0-9_-]{43}(?![A-Za-z0-9_-])',
);

const String _crockford = '0-9A-HJKMNP-TV-Z';

final RegExp _recoveryCode = RegExp(
  '(?<![A-Za-z0-9-])[$_crockford]{4}-[$_crockford]{4}-[$_crockford]{4}'
  '(?![A-Za-z0-9-])',
);

final RegExp _inviteCode = RegExp('MLN-[$_crockford]{4}(?![A-Za-z0-9])');

final RegExp _upper = RegExp('[A-Z]');
final RegExp _lower = RegExp('[a-z]');
final RegExp _digit = RegExp('[0-9]');

final class LogSecretsCheck {
  const LogSecretsCheck(this.text, this.found);

  final String text;
  final Map<String, int> found;

  int get total => found.values.fold(0, (sum, n) => sum + n);

  bool get clean => total == 0;

  String get summary => found.isEmpty
      ? 'none'
      : [for (final e in found.entries) '${e.key}=${e.value}'].join(' ');
}

bool _alreadyMasked(String value) =>
    value.isEmpty || value.startsWith('***') || value.startsWith('<');

LogSecretsCheck maskLeakedSecrets(String text) {
  final found = <String, int>{};
  void hit(String kind) => found[kind] = (found[kind] ?? 0) + 1;

  var result = text.replaceAllMapped(_bearer, (m) {
    final token = m.group(2)!;
    if (_alreadyMasked(token)) return m.group(0)!;
    hit('bearer');
    return '${m.group(1)}${maskToken(token)}';
  });
  result = result.replaceAllMapped(_jwt, (m) {
    hit('jwt');
    return maskToken(m.group(0));
  });
  result = result.replaceAllMapped(_secretField, (m) {
    final value = m.group(2)!;
    if (_alreadyMasked(value)) return m.group(0)!;
    hit('field');
    return '${m.group(1)}${maskToken(value)}${m.group(3)}';
  });
  result = result.replaceAllMapped(_refreshToken, (m) {
    final value = m.group(0)!;
    if (!_upper.hasMatch(value) ||
        !_lower.hasMatch(value) ||
        !_digit.hasMatch(value)) {
      return value;
    }
    hit('token');
    return maskToken(value);
  });
  result = result.replaceAllMapped(_recoveryCode, (m) {
    final value = m.group(0)!;
    if (!_upper.hasMatch(value)) return value;
    hit('recoveryCode');
    return maskRecoveryCode(value);
  });
  result = result.replaceAllMapped(_inviteCode, (m) {
    hit('inviteCode');
    return maskInviteCode(m.group(0));
  });
  return LogSecretsCheck(result, Map.unmodifiable(found));
}
