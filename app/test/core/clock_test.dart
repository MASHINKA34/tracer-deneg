import 'package:flutter_test/flutter_test.dart';
import 'package:milionchik/core/clock.dart';
import 'package:shared/shared.dart';

void main() {
  test('today() — дата телефона из now(): 23:59:59 ещё 19-е, полночь '
      'уже 20-е', () {
    final late = Clock(now: () => DateTime(2026, 10, 19, 23, 59, 59));
    final midnight = Clock(now: () => DateTime(2026, 10, 20));

    expect(late.now(), DateTime(2026, 10, 19, 23, 59, 59));
    expect(late.today(), LocalDate(2026, 10, 19));
    expect(midnight.today(), LocalDate(2026, 10, 20));
  });

  test('по умолчанию часы — системное время телефона', () {
    final before = DateTime.now();
    final now = const Clock().now();
    final after = DateTime.now();

    expect(now.isBefore(before), isFalse);
    expect(now.isAfter(after), isFalse);
    expect(now.isUtc, isFalse);
  });
}
