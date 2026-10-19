import 'dart:async';
import 'dart:math';

/// Ключ зоны, в которой лежит id запроса или задачи (rid).
///
/// Всё, что выполняется внутри [runWithRequestId], включая асинхронные
/// продолжения, пишет в лог `rid=…` — цепочка одной операции находится grep'ом.
const Symbol requestIdZoneKey = #milionchikRequestId;

final Random _random = Random.secure();
final RegExp _validRequestId = RegExp(r'^[A-Za-z0-9._-]{1,64}$');

/// Выполняет [body] в зоне с id запроса [requestId].
R runWithRequestId<R>(String requestId, R Function() body) =>
    runZoned(body, zoneValues: {requestIdZoneKey: requestId});

/// Id запроса из зоны [zone] или `null`, если зона без него.
String? requestIdOf(Zone? zone) {
  final value = zone?[requestIdZoneKey];
  return value is String ? value : null;
}

/// Id запроса текущей зоны или `null`.
String? currentRequestId() => requestIdOf(Zone.current);

/// Новый id: 16 hex-символов (64 случайных бита).
String generateRequestId() {
  final buffer = StringBuffer();
  for (var i = 0; i < 8; i++) {
    buffer.write(_random.nextInt(256).toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}

/// Можно ли принять чужой id (заголовок `X-Request-Id`): 1–64 символа
/// `[A-Za-z0-9._-]`, чтобы в лог не попал мусор или перевод строки.
bool isValidRequestId(String? value) =>
    value != null && _validRequestId.hasMatch(value);
