import 'package:drift/drift.dart';
import 'package:shared/shared.dart';

class LocalDateConverter extends TypeConverter<LocalDate, String> {
  const LocalDateConverter();

  @override
  LocalDate fromSql(String fromDb) => LocalDate.parse(fromDb);

  @override
  String toSql(LocalDate value) => value.toJson();
}

class YearMonthConverter extends TypeConverter<YearMonth, String> {
  const YearMonthConverter();

  @override
  YearMonth fromSql(String fromDb) => YearMonth.parse(fromDb);

  @override
  String toSql(YearMonth value) => value.toJson();
}

class InstantConverter extends TypeConverter<DateTime, String> {
  const InstantConverter();

  @override
  DateTime fromSql(String fromDb) => decodeInstant(fromDb);

  @override
  String toSql(DateTime value) => encodeInstant(value);
}
