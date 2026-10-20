import 'package:shared/shared.dart';
import 'package:test/test.dart';

Matcher formatError(String message) => throwsA(
  isA<FormatException>().having((e) => e.message, 'message', message),
);

void main() {
  group('JsonReader', () {
    final r = JsonReader({
      'name': 'Кафе',
      'count': 3,
      'flag': true,
      'tags': ['a', 'b'],
      'mixed': ['a', 1],
      'items': [
        {'x': 1},
      ],
      'nested': {'k': 'v'},
      'nothing': null,
      'kind': 'shared',
    }, 'Test');

    test('обязательные и необязательные поля', () {
      expect(r.string('name'), 'Кафе');
      expect(r.integer('count'), 3);
      expect(r.boolean('flag'), isTrue);
      expect(r.optString('nothing'), isNull);
      expect(r.optInteger('missing'), isNull);
      expect(r.optInstant('nothing'), isNull);
      expect(r.optMonth('nothing'), isNull);
      expect(r.optEnumByName('nothing', BudgetKind.values), isNull);
      expect(r.enumByName('kind', BudgetKind.values), BudgetKind.shared);
      expect(r.strings('tags'), ['a', 'b']);
      expect(r.objects('items', (j) => (j! as Map)['x']), [1]);
      expect(r.optObject('nested'), {'k': 'v'});
      expect(r.optObject('nothing'), isNull);
    });

    test('понятные ошибки', () {
      expect(
        () => r.string('count'),
        formatError('Test.count: expected string, got int'),
      );
      expect(
        () => r.integer('missing'),
        formatError('Test.missing: expected int, got nothing'),
      );
      expect(
        () => r.optString('count'),
        formatError('Test.count: expected string or null, got int'),
      );
      expect(
        () => r.strings('mixed'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            startsWith('Test.mixed: expected list of strings, got List'),
          ),
        ),
      );
      expect(() => r.optObject('name'), throwsFormatException);
      expect(() => r.date('name'), throwsFormatException);
      expect(() => r.instant('name'), throwsFormatException);
      expect(() => r.month('name'), throwsFormatException);
      expect(
        () => r.enumByName('name', BudgetKind.values),
        formatError(
          'Test.name: unknown value "Кафе", expected one of personal, shared',
        ),
      );
    });

    test('не объект', () {
      expect(
        () => JsonReader.of([1], 'Test'),
        formatError('Test: expected JSON object, got List<int>'),
      );
    });
  });

  test('SyncRecord: значение по умолчанию copyWith отличается от null', () {
    expect(identical(keep, null), isFalse);
  });
}
