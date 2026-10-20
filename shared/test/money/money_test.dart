import 'package:shared/shared.dart';
import 'package:test/test.dart';

/// Неразрывный пробел в эталонах.
const _ = ' ';

void main() {
  group('Money', () {
    test('рубли и копейки', () {
      expect(const Money.rubles(149, 90).kopecks, 14990);
      expect(const Money(14990).wholeRubles, 149);
      expect(const Money(14990).kopecksPart, 90);
      expect(const Money(-14990).kopecksPart, 90);
    });

    test('округление до рубля — половина вверх', () {
      expect(const Money(1829950).roundedRubles, 18300);
      expect(const Money(1829949).roundedRubles, 18299);
      expect(const Money(50).roundedRubles, 1);
      expect(const Money(49).roundedRubles, 0);
      expect(const Money(-150).roundedRubles, -2);
    });

    test('арифметика и сравнение', () {
      const a = Money(100);
      const b = Money(250);
      expect(a + b, const Money(350));
      expect(b - a, const Money(150));
      expect(-a, const Money(-100));
      expect((-a).abs, a);
      expect(a < b, isTrue);
      expect(a <= a, isTrue);
      expect(b > a, isTrue);
      expect(b >= b, isTrue);
      expect(a.compareTo(b), lessThan(0));
      expect(Money.sum([a, b, a]), const Money(450));
      expect(Money.sum(const []), Money.zero);
      expect(Money.zero.isZero, isTrue);
      expect(a.isPositive, isTrue);
      expect((-a).isNegative, isTrue);
      expect(a.hashCode, const Money(100).hashCode);
      expect(a.toJson(), 100);
      expect(a.toString(), 'Money(100)');
    });

    test('формат в списке: копейки только если не ноль', () {
      expect(const Money.rubles(640).format(), '640$_₽');
      expect(const Money.rubles(1280).format(), '1${_}280$_₽');
      expect(const Money(14990).format(), '149,90$_₽');
      expect(const Money(5).format(), '0,05$_₽');
      expect(const Money.rubles(10000000).format(), '10${_}000${_}000$_₽');
      expect(const Money(-14990).format(), '−149,90$_₽');
    });

    test('формат итога: до рубля', () {
      expect(const Money(1829950).formatTotal(), '18${_}300$_₽');
      expect(const Money(1829949).formatTotal(), '18${_}299$_₽');
      expect(Money.zero.formatTotal(), '0$_₽');
      expect(const Money(-150).formatTotal(), '−2$_₽');
    });

    test('ячейка календаря: до 10 000 — число с группами', () {
      expect(const Money.rubles(2340).formatCell(), '2${_}340');
      expect(const Money.rubles(9999).formatCell(), '9${_}999');
      expect(const Money.rubles(440).formatCell(), '440');
      expect(Money.zero.formatCell(), '0');
      expect(const Money(40).formatCell(), '0');
      expect(const Money(50).formatCell(), '1');
    });

    test('ячейка календаря: от 10 000 — «к» с округлением', () {
      expect(const Money.rubles(12400).formatCell(), '12,4к');
      expect(const Money.rubles(12000).formatCell(), '12к');
      expect(const Money.rubles(12449).formatCell(), '12,4к');
      expect(const Money.rubles(12450).formatCell(), '12,5к');
      expect(const Money.rubles(10000).formatCell(), '10к');
      // 9 999,50 ₽ округляется до 10 000 — уже «к».
      expect(const Money(999950).formatCell(), '10к');
      expect(const Money.rubles(99960).formatCell(), '100к');
      expect(const Money.rubles(999949).formatCell(), '999,9к');
    });

    test('ячейка календаря: от 1 000 000 — «м»', () {
      expect(const Money.rubles(999950).formatCell(), '1м');
      expect(const Money.rubles(1000000).formatCell(), '1м');
      expect(const Money.rubles(1240000).formatCell(), '1,2м');
      expect(const Money.rubles(1250000).formatCell(), '1,3м');
      expect(const Money.rubles(12345678).formatCell(), '12,3м');
      expect(const Money.rubles(-12400).formatCell(), '−12,4к');
    });
  });

  group('groupDigits', () {
    test('группы по 3 через неразрывный пробел', () {
      expect(groupDigits(0), '0');
      expect(groupDigits(999), '999');
      expect(groupDigits(1000), '1${_}000');
      expect(groupDigits(1234567), '1${_}234${_}567');
      expect(groupDigits(-1000), '−1${_}000');
    });
  });
}
