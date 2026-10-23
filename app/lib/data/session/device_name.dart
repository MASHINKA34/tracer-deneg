import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:shared/logging.dart';

import '../../core/logging/device_info.dart';

final _log = Logger('session');

const String fallbackDeviceName = 'Android';

typedef ReadDeviceInfo = DeviceInfo Function();

String deviceNameOf(DeviceInfo device) {
  final model = device.model.trim();
  if (model.isEmpty || model == DeviceInfo.unknown.model) {
    return fallbackDeviceName;
  }
  return model;
}

String readDeviceName([ReadDeviceInfo read = DeviceInfo.read]) {
  final DeviceInfo device;
  try {
    device = read();
  } catch (e, st) {
    _log.warning(
      'device model unavailable → deviceName=$fallbackDeviceName: '
      '${describeError(e)}',
      e,
      st,
    );
    return fallbackDeviceName;
  }
  final name = deviceNameOf(device);
  if (name == fallbackDeviceName) {
    _log.info(
      'device model empty (model=${device.model}) → '
      'deviceName=$fallbackDeviceName',
    );
  } else {
    _log.fine('deviceName=$name from device model');
  }
  return name;
}

final deviceNameProvider = Provider<String>(
  (ref) => readDeviceName(),
  name: 'deviceName',
);
