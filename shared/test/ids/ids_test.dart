import 'package:shared/shared.dart';
import 'package:test/test.dart';

void main() {
  test('UUID v5: эталон RFC 9562, приложение A.4', () {
    // Namespace DNS + "www.example.com".
    expect(
      uuidV5('6ba7b810-9dad-11d1-80b4-00c04fd430c8', 'www.example.com'),
      '2ed6657d-e927-568b-95e1-2665a8aea6a2',
    );
  });

  test('newId — UUID v4, каждый раз новый', () {
    final ids = {for (var i = 0; i < 1000; i++) newId()};
    expect(ids, hasLength(1000));
    for (final id in ids.take(20)) {
      expect(isUuid(id), isTrue, reason: id);
      expect(id[14], '4');
      expect('89ab', contains(id[19]));
    }
  });

  test('isUuid — только канонический вид', () {
    expect(isUuid('2ed6657d-e927-568b-95e1-2665a8aea6a2'), isTrue);
    expect(isUuid('2ED6657D-E927-568B-95E1-2665A8AEA6A2'), isFalse);
    expect(isUuid('2ed6657de927568b95e12665a8aea6a2'), isFalse);
    expect(isUuid(''), isFalse);
  });
}
