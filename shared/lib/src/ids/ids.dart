import 'package:uuid/uuid.dart';

const Uuid _uuid = Uuid();

final RegExp _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);

/// Новый id записи — UUID v4 из криптостойкого генератора (00-spec §8:
/// id генерирует тот, кто создаёт запись).
String newId() => _uuid.v4();

/// UUID v5 (SHA-1) от [name] в пространстве имён [namespace] (RFC 9562).
String uuidV5(String namespace, String name) => _uuid.v5(namespace, name);

/// Строка — UUID в каноническом виде (нижний регистр, с дефисами).
bool isUuid(String value) => _uuidPattern.hasMatch(value);
