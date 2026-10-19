import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

typedef _PropGetNative = Int32 Function(
  Pointer<Utf8> name,
  Pointer<Utf8> value,
);
typedef _PropGetDart = int Function(Pointer<Utf8> name, Pointer<Utf8> value);

/// PROP_VALUE_MAX из sys/system_properties.h.
const int _propValueMax = 92;

/// Устройство для лога старта и отчётов об ошибках: уровень Android SDK,
/// модель, производитель. Читается синхронно из системных свойств (FFI).
class DeviceInfo {
  const DeviceInfo({
    required this.sdkInt,
    required this.release,
    required this.model,
    required this.manufacturer,
  });

  /// Не Android (тесты на компьютере) — пустые значения.
  static const unknown = DeviceInfo(
    sdkInt: null,
    release: '?',
    model: '?',
    manufacturer: '?',
  );

  final int? sdkInt;
  final String release;
  final String model;
  final String manufacturer;

  /// Читает `ro.build.version.sdk`, `ro.build.version.release`,
  /// `ro.product.model`, `ro.product.manufacturer`.
  static DeviceInfo read() {
    if (!Platform.isAndroid) return unknown;
    final get = DynamicLibrary.open('libc.so')
        .lookupFunction<_PropGetNative, _PropGetDart>('__system_property_get');

    String prop(String name) {
      final namePtr = name.toNativeUtf8();
      final value = malloc<Uint8>(_propValueMax).cast<Utf8>();
      try {
        final length = get(namePtr, value);
        return length > 0 ? value.toDartString(length: length) : '';
      } finally {
        malloc.free(namePtr);
        malloc.free(value);
      }
    }

    return DeviceInfo(
      sdkInt: int.tryParse(prop('ro.build.version.sdk')),
      release: prop('ro.build.version.release'),
      model: prop('ro.product.model'),
      manufacturer: prop('ro.product.manufacturer'),
    );
  }
}
