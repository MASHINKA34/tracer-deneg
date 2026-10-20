/// Синхронизируемые сущности — значение `entity` в `/sync/push`.
enum SyncEntity { budget, category, expense, recurring }

/// Общие поля синхронизируемых сущностей (00-spec §8).
abstract interface class SyncRecord {
  String get id;

  /// Момент правки на клиенте (UTC) — по нему «последняя правка побеждает».
  DateTime get updatedAt;

  /// Кто правил (userId).
  String get updatedBy;

  /// Надгробие: момент удаления или `null`.
  DateTime? get deletedAt;

  /// Номер изменения на сервере (`null`, пока сервер не видел запись).
  int? get seq;

  /// Удалена ли запись (есть надгробие).
  bool get isDeleted;

  /// Тип сущности для синхронизации.
  SyncEntity get syncEntity;

  Map<String, Object?> toJson();
}

/// Значение по умолчанию в `copyWith`: «поле не меняем» (отличается от
/// `null`, которым поле можно очистить).
const Object keep = _Keep();

final class _Keep {
  const _Keep();
}
