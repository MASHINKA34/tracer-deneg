import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milionchik/core/orientation_policy.dart';

void main() {
  test('телефон (sw < 600 dp) — только портрет', () {
    expect(preferredOrientationsFor(320), [DeviceOrientation.portraitUp]);
    expect(preferredOrientationsFor(360), [DeviceOrientation.portraitUp]);
    expect(preferredOrientationsFor(599.9), [DeviceOrientation.portraitUp]);
  });

  test('планшет и раскрытая раскладушка (sw ≥ 600 dp) — без ограничений', () {
    expect(preferredOrientationsFor(600), isEmpty);
    expect(preferredOrientationsFor(840), isEmpty);
  });
}
