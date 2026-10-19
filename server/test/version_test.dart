import 'dart:io';

import 'package:server/version.dart';
import 'package:test/test.dart';

void main() {
  test('serverVersion совпадает с version в pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(
      r'^version:\s*(\S+)',
      multiLine: true,
    ).firstMatch(pubspec);
    expect(match?.group(1), serverVersion);
  });
}
