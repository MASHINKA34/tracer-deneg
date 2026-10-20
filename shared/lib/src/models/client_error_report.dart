import 'json.dart';

/// Максимальный размер логов в отчёте об ошибке: 200 КБ (00-spec §8).
const int maxClientErrorLogsBytes = 200 * 1024;

/// Вид отчёта об ошибке.
enum ClientErrorKind {
  crash('crash'),
  error('error'),
  userReport('user_report');

  const ClientErrorKind(this.code);

  /// Значение в JSON.
  final String code;

  static ClientErrorKind? fromCode(String code) {
    for (final value in values) {
      if (value.code == code) return value;
    }
    return null;
  }
}

/// Тело `POST /client-errors` — отчёт об ошибке без личных данных
/// (сервер добавляет id, receivedAt и userId, если есть токен).
final class ClientErrorReport {
  const ClientErrorReport({
    required this.appVersion,
    required this.androidSdk,
    required this.deviceModel,
    required this.kind,
    required this.message,
    this.stack,
    this.logs,
  });

  factory ClientErrorReport.fromJson(Object? json) {
    final r = JsonReader.of(json, 'ClientErrorReport');
    final kindCode = r.string('kind');
    final kind = ClientErrorKind.fromCode(kindCode);
    if (kind == null) {
      throw FormatException(
        'ClientErrorReport.kind: unknown value "$kindCode"',
      );
    }
    return ClientErrorReport(
      appVersion: r.string('appVersion'),
      androidSdk: r.optInteger('androidSdk'),
      deviceModel: r.optString('deviceModel'),
      kind: kind,
      message: r.string('message'),
      stack: r.optString('stack'),
      logs: r.optString('logs'),
    );
  }

  /// Версия и сборка приложения: `1.0.0+1`.
  final String appVersion;

  /// Уровень API Android или `null` (не Android).
  final int? androidSdk;
  final String? deviceModel;
  final ClientErrorKind kind;

  /// Тип и сообщение ошибки.
  final String message;
  final String? stack;

  /// Последние логи (до [maxClientErrorLogsBytes]).
  final String? logs;

  Map<String, Object?> toJson() => {
    'appVersion': appVersion,
    'androidSdk': androidSdk,
    'deviceModel': deviceModel,
    'kind': kind.code,
    'message': message,
    'stack': stack,
    'logs': logs,
  };

  @override
  bool operator ==(Object other) =>
      other is ClientErrorReport &&
      other.appVersion == appVersion &&
      other.androidSdk == androidSdk &&
      other.deviceModel == deviceModel &&
      other.kind == kind &&
      other.message == message &&
      other.stack == stack &&
      other.logs == logs;

  @override
  int get hashCode => Object.hash(
    appVersion,
    androidSdk,
    deviceModel,
    kind,
    message,
    stack,
    logs,
  );

  @override
  String toString() =>
      'ClientErrorReport(${kind.code} app=$appVersion sdk=$androidSdk '
      'logs=${logs?.length ?? 0} chars)';
}
