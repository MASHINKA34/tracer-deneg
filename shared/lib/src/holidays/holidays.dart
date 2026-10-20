import '../time/local_date.dart';
import '../time/month_day.dart';
import '../time/year_month.dart';
import 'easter.dart';

/// Сезон (00-spec §7.6.1).
enum Season { winter, spring, summer, autumn }

/// Сезон месяца [month] (1–12): декабрь–февраль — зима, март–май — весна,
/// июнь–август — лето, сентябрь–ноябрь — осень.
Season seasonOf(int month) {
  RangeError.checkValueInInterval(month, 1, 12, 'month');
  return switch (month) {
    12 || 1 || 2 => Season.winter,
    3 || 4 || 5 => Season.spring,
    6 || 7 || 8 => Season.summer,
    _ => Season.autumn,
  };
}

/// 11 праздников (00-spec §7.6.2). Порядок — порядок таблицы: он же
/// приоритет при равенстве. Имя значения — ключ (`newyear`, …) в настройках
/// аккаунта, токенах и ARB.
enum HolidayKey {
  newyear('🎄'),
  valentine('💌'),
  defender('⭐'),
  maslenitsa('🥞'),
  women('🌷'),
  labour('🔨'),
  victory('🎆'),
  children('🎈'),
  knowledge('📚'),
  halloween('🎃'),
  birthday('🎂');

  const HolidayKey(this.emoji);

  /// Эмодзи отметки в календаре и наклейки на «+».
  final String emoji;

  /// Ключ для JSON и настроек.
  String get key => name;

  /// Праздник по ключу или `null`, если ключ неизвестен.
  static HolidayKey? fromKey(String key) {
    for (final value in values) {
      if (value.name == key) return value;
    }
    return null;
  }
}

/// Фаза праздника на дату: до «дня», в «день», после «дня» в пределах
/// периода.
enum HolidayStage { before, day, after }

/// Один конкретный праздник: период оформления и его «день».
final class HolidayOccurrence {
  const HolidayOccurrence({
    required this.key,
    required this.start,
    required this.day,
    required this.end,
  });

  final HolidayKey key;

  /// Первый день оформления.
  final LocalDate start;

  /// «День» праздника (для Масленицы — Прощёное воскресенье).
  final LocalDate day;

  /// Последний день оформления.
  final LocalDate end;

  /// Ключ «праздник+год» (год «дня»): `newyear:2027` и 20.12.2026, и
  /// 5.01.2027. По нему плашка прячется до следующего праздника.
  String get id => '${key.name}:${day.year}';

  /// Дни с эмодзи-отметкой: «день», у Нового года ещё 31 декабря.
  List<LocalDate> get markDays =>
      key == HolidayKey.newyear ? [day.addDays(-1), day] : [day];

  /// Входит ли [date] в период оформления.
  bool contains(LocalDate date) => date >= start && date <= end;

  /// Фаза на [date] или `null`, если [date] вне периода.
  HolidayPhase? phaseOn(LocalDate date) =>
      contains(date) ? HolidayPhase._(this, date) : null;

  @override
  bool operator ==(Object other) =>
      other is HolidayOccurrence &&
      other.key == key &&
      other.start == start &&
      other.day == day &&
      other.end == end;

  @override
  int get hashCode => Object.hash(key, start, day, end);

  @override
  String toString() => 'HolidayOccurrence(${key.name} $start..$end day=$day)';
}

/// Праздник на конкретную дату — данные для плашки (тексты — в ARB).
final class HolidayPhase {
  const HolidayPhase._(this.occurrence, this.date);

  final HolidayOccurrence occurrence;

  /// Дата, на которую считается фаза («сегодня»).
  final LocalDate date;

  HolidayKey get key => occurrence.key;

  HolidayStage get stage {
    final order = date.compareTo(occurrence.day);
    if (order < 0) return HolidayStage.before;
    if (order == 0) return HolidayStage.day;
    return HolidayStage.after;
  }

  /// Дней до «дня»: «До Нового года 7 дн.» 25 декабря; в «день» — 0,
  /// после — отрицательное.
  int get daysUntilDay => date.daysUntil(occurrence.day);

  /// Дней до конца периода: 4 мая у Недели труда — 3 («ещё 3 дня»).
  int get daysUntilEnd => date.daysUntil(occurrence.end);

  @override
  bool operator ==(Object other) =>
      other is HolidayPhase &&
      other.occurrence == occurrence &&
      other.date == date;

  @override
  int get hashCode => Object.hash(occurrence, date);

  @override
  String toString() => 'HolidayPhase(${key.name} ${stage.name} on $date)';
}

LocalDate _d(int year, int month, int day) => LocalDate(year, month, day);

/// Праздник [key], «день» которого приходится на год [year]. Для
/// [HolidayKey.birthday] нужна дата рождения [birthday] (6 дней до + сам
/// день), иначе [ArgumentError].
HolidayOccurrence holidayOccurrence(
  HolidayKey key,
  int year, {
  MonthDay? birthday,
}) {
  HolidayOccurrence fixed(int sm, int sd, int dm, int dd, int em, int ed) =>
      HolidayOccurrence(
        key: key,
        start: _d(year, sm, sd),
        day: _d(year, dm, dd),
        end: _d(year, em, ed),
      );

  switch (key) {
    case HolidayKey.newyear:
      return HolidayOccurrence(
        key: key,
        start: _d(year - 1, 12, 20),
        day: _d(year, 1, 1),
        end: _d(year, 1, 8),
      );
    case HolidayKey.valentine:
      return fixed(2, 8, 2, 14, 2, 14);
    case HolidayKey.defender:
      return fixed(2, 17, 2, 23, 2, 23);
    case HolidayKey.maslenitsa:
      final sunday = forgivenessSunday(year);
      return HolidayOccurrence(
        key: key,
        start: sunday.addDays(-6),
        day: sunday,
        end: sunday,
      );
    case HolidayKey.women:
      return fixed(3, 2, 3, 8, 3, 8);
    case HolidayKey.labour:
      return fixed(5, 1, 5, 1, 5, 7);
    case HolidayKey.victory:
      return fixed(5, 8, 5, 9, 5, 9);
    case HolidayKey.children:
      return fixed(5, 26, 6, 1, 6, 1);
    case HolidayKey.knowledge:
      return fixed(8, 26, 9, 1, 9, 1);
    case HolidayKey.halloween:
      return fixed(10, 25, 10, 31, 10, 31);
    case HolidayKey.birthday:
      if (birthday == null) {
        throw ArgumentError.notNull('birthday');
      }
      final day = birthday.inYear(year);
      return HolidayOccurrence(
        key: key,
        start: day.addDays(-6),
        day: day,
        end: day,
      );
  }
}

/// Все праздники, в период которых попадает [date] (без учёта настроек),
/// в порядке таблицы. День рождения — если задан [birthday].
List<HolidayOccurrence> holidaysOn(LocalDate date, {MonthDay? birthday}) {
  final result = <HolidayOccurrence>[];
  for (final key in HolidayKey.values) {
    if (key == HolidayKey.birthday && birthday == null) continue;
    // Период может начаться в прошлом году («день» — в следующем), поэтому
    // проверяем праздник этого и следующего года.
    for (final year in [date.year, date.year + 1]) {
      if (year > 9999) continue;
      final occurrence = holidayOccurrence(key, year, birthday: birthday);
      if (occurrence.contains(date)) result.add(occurrence);
    }
  }
  return result;
}

/// Отметки месяца [month]: число → праздники с отметкой в этот день — все
/// праздники независимо от настроек и свой день рождения [birthday].
/// Порядок в списке — приоритет: день рождения, затем порядок таблицы.
Map<int, List<HolidayKey>> monthMarks(YearMonth month, {MonthDay? birthday}) {
  final marks = <int, List<HolidayKey>>{};
  void add(LocalDate date, HolidayKey key) {
    if (month.contains(date)) (marks[date.day] ??= []).add(key);
  }

  if (birthday != null) add(birthday.inYear(month.year), HolidayKey.birthday);
  for (final key in HolidayKey.values) {
    if (key == HolidayKey.birthday) continue;
    // Отметка 31 декабря принадлежит Новому году следующего года.
    for (final year in [month.year, month.year + 1]) {
      if (year > 9999) continue;
      for (final date in holidayOccurrence(key, year).markDays) {
        add(date, key);
      }
    }
  }
  return marks;
}

/// Эмодзи для ячеек месяца: число → одна отметка с наибольшим приоритетом.
Map<int, String> monthMarkEmojis(YearMonth month, {MonthDay? birthday}) => {
  for (final entry in monthMarks(month, birthday: birthday).entries)
    entry.key: entry.value.first.emoji,
};
