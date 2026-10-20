import '../time/local_date.dart';
import '../time/month_day.dart';
import 'holidays.dart';

/// «Настроение» оформления: 4 сезона + 11 праздников. Имя значения — ключ
/// палитры `mood/*` в `design-tokens.json`.
enum Mood {
  winter,
  spring,
  summer,
  autumn,
  newyear,
  valentine,
  defender,
  maslenitsa,
  women,
  labour,
  victory,
  children,
  knowledge,
  halloween,
  birthday;

  /// Настроение сезона.
  static Mood ofSeason(Season season) => switch (season) {
    Season.winter => Mood.winter,
    Season.spring => Mood.spring,
    Season.summer => Mood.summer,
    Season.autumn => Mood.autumn,
  };

  /// Настроение праздника.
  static Mood ofHoliday(HolidayKey key) => Mood.values.byName(key.name);

  /// Ключ палитры.
  String get key => name;

  /// Сезон, если это сезонное настроение.
  Season? get season => Season.values.asNameMap()[name];

  /// Праздник, если это праздничное настроение.
  HolidayKey? get holiday => HolidayKey.fromKey(name);
}

/// Настройки праздников аккаунта (00-spec §7.6.5).
final class HolidaySettings {
  const HolidaySettings({
    this.enabled = true,
    this.disabled = const {},
    this.birthday,
  });

  /// Общий переключатель «Праздники».
  final bool enabled;

  /// Выключенные праздники (`birthday` — «Дни рождения»).
  final Set<HolidayKey> disabled;

  /// Свой день рождения или `null`.
  final MonthDay? birthday;

  @override
  bool operator ==(Object other) =>
      other is HolidaySettings &&
      other.enabled == enabled &&
      other.birthday == birthday &&
      other.disabled.length == disabled.length &&
      other.disabled.containsAll(disabled);

  @override
  int get hashCode =>
      Object.hash(enabled, birthday, Object.hashAllUnordered(disabled));

  @override
  String toString() =>
      'HolidaySettings(enabled: $enabled, '
      'disabled: ${disabled.map((k) => k.name).toList()}, '
      'birthday: ${birthday != null ? 'set' : 'none'})';
}

/// Праздник, который задаёт оформление на [date] (00-spec §7.6.3), или
/// `null` — тогда сезон:
/// 1. праздники выключены целиком → `null`;
/// 2. кандидаты — включённые праздники, в период которых попадает [date],
///    и свой день рождения, если задан и включён;
/// 3. есть день рождения → он;
/// 4. иначе — с наименьшим |date − «день»|, при равенстве — выше в таблице.
HolidayPhase? activeHoliday(LocalDate date, HolidaySettings settings) {
  if (!settings.enabled) return null;
  final birthday = settings.disabled.contains(HolidayKey.birthday)
      ? null
      : settings.birthday;
  final candidates = holidaysOn(
    date,
    birthday: birthday,
  ).where((o) => !settings.disabled.contains(o.key)).toList();
  if (candidates.isEmpty) return null;

  HolidayOccurrence? best;
  for (final candidate in candidates) {
    if (candidate.key == HolidayKey.birthday) return candidate.phaseOn(date);
    if (best == null ||
        date.daysUntil(candidate.day).abs() < date.daysUntil(best.day).abs()) {
      // Кандидаты идут в порядке таблицы, поэтому при равенстве остаётся
      // тот, что выше.
      best = candidate;
    }
  }
  return best!.phaseOn(date);
}

/// Настроение на [date]: праздник из [activeHoliday] или сезон месяца.
Mood moodOn(LocalDate date, HolidaySettings settings) {
  final holiday = activeHoliday(date, settings);
  return holiday != null
      ? Mood.ofHoliday(holiday.key)
      : Mood.ofSeason(seasonOf(date.month));
}
