import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/core/logging/device_info.dart';
import 'package:milionchik/data/session/device_name.dart';

import '../api/fake_api_adapter.dart';

DeviceInfo _device(String model) =>
    DeviceInfo(sdkInt: 36, release: '16', model: model, manufacturer: 'Google');

void main() {
  late LogCapture logs;

  setUp(() => logs = LogCapture());

  tearDown(() => logs.dispose());

  test('deviceName - модель телефона из DeviceInfo', () {
    expect(deviceNameOf(_device('Pixel 7')), 'Pixel 7');
    expect(
      readDeviceName(() => _device('sdk_gphone64_x86_64')),
      'sdk_gphone64_x86_64',
    );
  });

  test('модель неизвестна или пустая - deviceName «Android», info в лог', () {
    expect(deviceNameOf(DeviceInfo.unknown), fallbackDeviceName);
    expect(deviceNameOf(_device('   ')), fallbackDeviceName);
    expect(readDeviceName(() => DeviceInfo.unknown), 'Android');
    expect(
      logs.linesOf('session', Level.INFO).single,
      endsWith('device model empty (model=?) → deviceName=Android'),
    );
  });

  test('чтение модели упало - deviceName «Android», warn с типом', () {
    expect(readDeviceName(() => throw UnsupportedError('no libc')), 'Android');
    final warning = logs.linesOf('session', Level.WARNING).single;
    expect(
      warning,
      contains(
        'device model unavailable → deviceName=Android: '
        'UnsupportedError',
      ),
    );
    expect(warning, contains('stack:'));
  });
}
