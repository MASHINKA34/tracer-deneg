/// Генератор случайных чисел mulberry32 — тот же, что в генераторе декора
/// Figma (JS). Одинаковый сид → одинаковая последовательность, поэтому узор
/// совпадает с макетом. Арифметика 32-битная, как в JS; умножение — без
/// переполнения и в вебе (числа там — double).
final class Mulberry32 {
  Mulberry32(int seed) : _a = seed.toSigned(32);

  int _a;

  /// Следующее число в [0, 1).
  double next() {
    _a = (_a + 0x6D2B79F5).toSigned(32);
    var t = _imul(_a ^ (_a.toUnsigned(32) >> 15), 1 | _a);
    t = (t + _imul(t ^ (t.toUnsigned(32) >> 7), 61 | t)).toSigned(32) ^ t;
    return (t ^ (t.toUnsigned(32) >> 14)).toUnsigned(32) / 4294967296;
  }

  /// `Math.imul`: произведение по модулю 2^32 как int32.
  static int _imul(int a, int b) {
    final x = a.toSigned(32);
    final y = b.toSigned(32);
    final xHi = (x >> 16) & 0xFFFF;
    final xLo = x & 0xFFFF;
    final yHi = (y >> 16) & 0xFFFF;
    final yLo = y & 0xFFFF;
    return (xLo * yLo + (((xHi * yLo + xLo * yHi) & 0xFFFF) << 16)).toSigned(
      32,
    );
  }
}
