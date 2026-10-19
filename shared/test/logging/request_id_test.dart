import 'dart:async';

import 'package:shared/logging.dart';
import 'package:test/test.dart';

void main() {
  test('generateRequestId: 16 hex-символов и разные значения', () {
    final ids = List.generate(100, (_) => generateRequestId());
    for (final id in ids) {
      expect(id, matches(RegExp(r'^[0-9a-f]{16}$')));
    }
    expect(ids.toSet(), hasLength(ids.length));
  });

  test('isValidRequestId', () {
    expect(isValidRequestId('7f3a-01.b_C'), isTrue);
    expect(isValidRequestId('a' * 64), isTrue);
    expect(isValidRequestId('a' * 65), isFalse);
    expect(isValidRequestId(''), isFalse);
    expect(isValidRequestId('a b'), isFalse);
    expect(isValidRequestId('a\nb'), isFalse);
    expect(isValidRequestId(null), isFalse);
  });

  test('id запроса виден в асинхронных продолжениях зоны', () async {
    expect(currentRequestId(), isNull);
    final seen = await runWithRequestId('rid-1', () async {
      await Future<void>.delayed(Duration.zero);
      return currentRequestId();
    });
    expect(seen, 'rid-1');
    expect(requestIdOf(Zone.root), isNull);
    expect(requestIdOf(null), isNull);
  });
}
