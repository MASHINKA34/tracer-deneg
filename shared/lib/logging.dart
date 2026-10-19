/// Формат строк лога, уровни, id запроса и маскировка секретов (00-spec §13).
///
/// Строка лога одинакова у приложения и сервера:
/// `2026-10-19T18:40:12.345+03:00 INFO  [sync] pull done cursor=1234 in 230ms rid=7f3a…`
library;

export 'src/logging/error_details.dart';
export 'src/logging/log_format.dart';
export 'src/logging/log_level.dart';
export 'src/logging/mask.dart';
export 'src/logging/request_id.dart';
