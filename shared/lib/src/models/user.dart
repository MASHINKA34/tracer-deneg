import '../holidays/holidays.dart';
import '../holidays/mood.dart';
import '../time/month_day.dart';
import 'json.dart';
import 'sync_record.dart';

/// Аккаунт пользователя, как его видит клиент (`/me`, ответы `/auth/*`):
/// без хешей пароля и кода восстановления (00-spec §8).
final class User {
  User({
    required this.id,
    required this.login,
    required this.displayName,
    this.birthday,
    this.holidaysEnabled = true,
    Set<String> holidaysDisabled = const {},
    required DateTime createdAt,
  }) : holidaysDisabled = Set.unmodifiable(holidaysDisabled),
       createdAt = normalizeInstant(createdAt);

  factory User.fromJson(Object? json) {
    final r = JsonReader.of(json, 'User');
    return User(
      id: r.string('id'),
      login: r.string('login'),
      displayName: r.string('displayName'),
      birthday: MonthDay.fromParts(
        r.optInteger('birthdayMonth'),
        r.optInteger('birthdayDay'),
      ),
      holidaysEnabled: r.boolean('holidaysEnabled'),
      holidaysDisabled: r.strings('holidaysDisabled').toSet(),
      createdAt: r.instant('createdAt'),
    );
  }

  final String id;

  /// Логин в нижнем регистре.
  final String login;
  final String displayName;
  final MonthDay? birthday;

  /// Общий переключатель «Праздники».
  final bool holidaysEnabled;

  /// Ключи выключенных праздников. Строки, а не [HolidayKey]: ключ из
  /// будущей версии не теряется при сохранении.
  final Set<String> holidaysDisabled;
  final DateTime createdAt;

  /// Настройки для выбора настроения; неизвестные ключи пропускаются.
  HolidaySettings get holidaySettings => HolidaySettings(
    enabled: holidaysEnabled,
    disabled: {for (final key in holidaysDisabled) ?HolidayKey.fromKey(key)},
    birthday: birthday,
  );

  User copyWith({
    String? displayName,
    Object? birthday = keep,
    bool? holidaysEnabled,
    Set<String>? holidaysDisabled,
  }) => User(
    id: id,
    login: login,
    displayName: displayName ?? this.displayName,
    birthday: identical(birthday, keep) ? this.birthday : birthday as MonthDay?,
    holidaysEnabled: holidaysEnabled ?? this.holidaysEnabled,
    holidaysDisabled: holidaysDisabled ?? this.holidaysDisabled,
    createdAt: createdAt,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'login': login,
    'displayName': displayName,
    'birthdayMonth': birthday?.month,
    'birthdayDay': birthday?.day,
    'holidaysEnabled': holidaysEnabled,
    'holidaysDisabled': holidaysDisabled.toList()..sort(),
    'createdAt': encodeInstant(createdAt),
  };

  @override
  bool operator ==(Object other) =>
      other is User &&
      other.id == id &&
      other.login == login &&
      other.displayName == displayName &&
      other.birthday == birthday &&
      other.holidaysEnabled == holidaysEnabled &&
      other.holidaysDisabled.length == holidaysDisabled.length &&
      other.holidaysDisabled.containsAll(holidaysDisabled) &&
      other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(
    id,
    login,
    displayName,
    birthday,
    holidaysEnabled,
    Object.hashAllUnordered(holidaysDisabled),
    createdAt,
  );

  /// Без логина, имени и даты рождения: личные данные не пишем в лог.
  @override
  String toString() => 'User($id holidays=$holidaysEnabled)';
}
