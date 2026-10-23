import 'package:shared/shared.dart';

import '../../data/api/api_error_text.dart';
import '../../l10n/app_localizations.dart';

enum AuthField { name, login, password, repeat }

sealed class AuthFieldError {
  const AuthFieldError();

  String get code;

  String text(AppLocalizations l10n);

  @override
  String toString() => code;
}

final class AuthInvalid extends AuthFieldError {
  const AuthInvalid(this.error);

  final ValidationError error;

  @override
  String get code => error.code;

  @override
  String text(AppLocalizations l10n) => authValidationText(l10n, error);

  @override
  bool operator ==(Object other) =>
      other is AuthInvalid && other.error == error;

  @override
  int get hashCode => error.hashCode;
}

final class AuthPasswordMismatch extends AuthFieldError {
  const AuthPasswordMismatch();

  @override
  String get code => 'password_mismatch';

  @override
  String text(AppLocalizations l10n) => l10n.authPasswordMismatch;

  @override
  bool operator ==(Object other) => other is AuthPasswordMismatch;

  @override
  int get hashCode => code.hashCode;
}

final class AuthRejected extends AuthFieldError {
  const AuthRejected(this.reason);

  final ApiErrorCode reason;

  @override
  String get code => reason.code;

  @override
  String text(AppLocalizations l10n) => apiErrorCodeText(l10n, reason);

  @override
  bool operator ==(Object other) =>
      other is AuthRejected && other.reason == reason;

  @override
  int get hashCode => reason.hashCode;
}

typedef AuthFieldErrors = Map<AuthField, AuthFieldError>;

String authValidationText(AppLocalizations l10n, ValidationError error) =>
    switch (error) {
      ValidationError.loginEmpty => l10n.authLoginEmpty,
      ValidationError.loginInvalidChars => l10n.authLoginInvalidChars,
      ValidationError.loginTooShort => l10n.authLoginTooShort(loginMinLength),
      ValidationError.loginTooLong => l10n.authLoginTooLong(loginMaxLength),
      ValidationError.passwordEmpty => l10n.authPasswordEmpty,
      ValidationError.passwordTooShort => l10n.authPasswordTooShort(
        passwordMinLength,
      ),
      ValidationError.passwordTooLong => l10n.authPasswordTooLong(
        passwordMaxLength,
      ),
      ValidationError.nameEmpty => l10n.authNameEmpty,
      ValidationError.nameTooLong => l10n.authNameTooLong(displayNameMaxLength),
      _ => l10n.apiErrorValidationFailed,
    };

AuthFieldErrors validateLoginForm({
  required String login,
  required String password,
}) => {
  if (validateLogin(login) case final error?)
    AuthField.login: AuthInvalid(error),
  if (validatePassword(password) case final error?)
    AuthField.password: AuthInvalid(error),
};

AuthFieldErrors validateRegisterForm({
  required String name,
  required String login,
  required String password,
  required String repeat,
}) {
  final passwordError = validatePassword(password);
  return {
    if (validateDisplayName(name) case final error?)
      AuthField.name: AuthInvalid(error),
    if (validateLogin(login) case final error?)
      AuthField.login: AuthInvalid(error),
    if (passwordError != null) AuthField.password: AuthInvalid(passwordError),
    if (passwordError == null && repeat != password)
      AuthField.repeat: const AuthPasswordMismatch(),
  };
}

AuthField? fieldOfValidation(ValidationError error) => switch (error) {
  ValidationError.loginEmpty ||
  ValidationError.loginInvalidChars ||
  ValidationError.loginTooShort ||
  ValidationError.loginTooLong => AuthField.login,
  ValidationError.passwordEmpty ||
  ValidationError.passwordTooShort ||
  ValidationError.passwordTooLong => AuthField.password,
  ValidationError.nameEmpty || ValidationError.nameTooLong => AuthField.name,
  _ => null,
};

String describeFieldErrors(AuthFieldErrors errors, List<AuthField> fields) =>
    fields.map((f) => '${f.name}=${errors[f]?.code ?? 'none'}').join(' ');

final class AuthRecoveryCodeInvalid extends AuthFieldError {
  const AuthRecoveryCodeInvalid({required this.empty});

  final bool empty;

  @override
  String get code => empty ? 'recovery_code_empty' : 'recovery_code_malformed';

  @override
  String text(AppLocalizations l10n) =>
      empty ? l10n.authRecoveryCodeEmpty : l10n.authRecoveryCodeInvalid;

  @override
  bool operator ==(Object other) =>
      other is AuthRecoveryCodeInvalid && other.empty == empty;

  @override
  int get hashCode => Object.hash(code, empty);
}

final class AuthRecoveryRejected extends AuthFieldError {
  const AuthRecoveryRejected();

  @override
  String get code => ApiErrorCode.badCredentials.code;

  @override
  String text(AppLocalizations l10n) => l10n.authRecoverBadCredentials;

  @override
  bool operator ==(Object other) => other is AuthRecoveryRejected;

  @override
  int get hashCode => code.hashCode;
}

enum RecoverField { login, code, password, repeat }

typedef RecoverFieldErrors = Map<RecoverField, AuthFieldError>;

RecoverFieldErrors validateRecoverForm({
  required String login,
  required String code,
  required String password,
  required String repeat,
}) {
  final passwordError = validatePassword(password);
  return {
    if (validateLogin(login) case final error?)
      RecoverField.login: AuthInvalid(error),
    if (code.trim().isEmpty)
      RecoverField.code: const AuthRecoveryCodeInvalid(empty: true)
    else if (normalizeRecoveryCode(code) == null)
      RecoverField.code: const AuthRecoveryCodeInvalid(empty: false),
    if (passwordError != null)
      RecoverField.password: AuthInvalid(passwordError),
    if (passwordError == null && repeat != password)
      RecoverField.repeat: const AuthPasswordMismatch(),
  };
}

RecoverField? recoverFieldOfValidation(ValidationError error) =>
    switch (fieldOfValidation(error)) {
      AuthField.login => RecoverField.login,
      AuthField.password => RecoverField.password,
      _ => null,
    };

String describeRecoverErrors(RecoverFieldErrors errors) => RecoverField.values
    .map((f) => '${f.name}=${errors[f]?.code ?? 'none'}')
    .join(' ');
