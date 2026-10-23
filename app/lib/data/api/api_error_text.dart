import 'package:shared/shared.dart';

import '../../l10n/app_localizations.dart';
import 'api_exception.dart';

String apiErrorText(AppLocalizations l10n, ApiException error) =>
    switch (error) {
      ApiErrorResponse(:final code, error: final body) =>
        code == null
            ? _serverMessage(l10n, body)
            : apiErrorCodeText(l10n, code),
      ApiServerFailure() => l10n.apiErrorServer,
      ApiNetworkFailure() => l10n.apiErrorNetwork,
      ApiTimeout() => l10n.apiErrorTimeout,
      ApiBadResponse() => l10n.apiErrorBadResponse,
      ApiSessionExpired() => l10n.apiErrorSessionExpired,
    };

String apiErrorCodeText(AppLocalizations l10n, ApiErrorCode code) =>
    switch (code) {
      ApiErrorCode.loginTaken => l10n.apiErrorLoginTaken,
      ApiErrorCode.badCredentials => l10n.apiErrorBadCredentials,
      ApiErrorCode.tooManyAttempts => l10n.apiErrorTooManyAttempts,
      ApiErrorCode.inviteNotFound => l10n.apiErrorInviteNotFound,
      ApiErrorCode.badRequest => l10n.apiErrorBadRequest,
      ApiErrorCode.validationFailed => l10n.apiErrorValidationFailed,
      ApiErrorCode.unauthorized => l10n.apiErrorUnauthorized,
      ApiErrorCode.sessionExpired => l10n.apiErrorSessionExpired,
      ApiErrorCode.notFound => l10n.apiErrorNotFound,
      ApiErrorCode.forbidden => l10n.apiErrorForbidden,
      ApiErrorCode.conflict => l10n.apiErrorConflict,
      ApiErrorCode.payloadTooLarge => l10n.apiErrorPayloadTooLarge,
      ApiErrorCode.internalError => l10n.apiErrorServer,
    };

String _serverMessage(AppLocalizations l10n, ApiError error) {
  final message = error.message.trim();
  return message.isEmpty ? l10n.apiErrorBadResponse : message;
}
