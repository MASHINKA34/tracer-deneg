import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

final class Clock {
  const Clock({this._now = DateTime.now});

  final DateTime Function() _now;

  DateTime now() => _now();

  LocalDate today() => LocalDate.fromDateTime(now());
}

final clockProvider = Provider<Clock>((ref) => const Clock(), name: 'clock');
