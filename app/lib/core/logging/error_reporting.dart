import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/client_errors_api.dart';
import '../../data/session/session_providers.dart';
import '../../data/session/session_state.dart';
import 'device_info.dart';
import 'error_report_sender.dart';
import 'error_reports.dart';

final class ReportDevice {
  const ReportDevice({
    required this.appVersion,
    required this.device,
    required this.buildMode,
    required this.logLevel,
  });

  static const unknown = ReportDevice(
    appVersion: '?',
    device: DeviceInfo.unknown,
    buildMode: '?',
    logLevel: '?',
  );

  final String appVersion;
  final DeviceInfo device;
  final String buildMode;
  final String logLevel;

  String describe() =>
      'manufacturer=${device.manufacturer} model=${device.model} '
      'android=${device.release} sdk=${device.sdkInt ?? '?'} '
      'app=$appVersion build=$buildMode log=$logLevel';
}

final class ErrorReporting {
  const ErrorReporting({
    required this.queue,
    required this.device,
    required this.logFiles,
  });

  final ErrorReportQueue queue;
  final ReportDevice device;
  final List<File> Function() logFiles;
}

final errorReportingProvider = Provider<ErrorReporting?>(
  (ref) => null,
  name: 'errorReporting',
);

final errorReportSenderProvider = Provider<ErrorReportSender?>((ref) {
  final reporting = ref.watch(errorReportingProvider);
  if (reporting == null) return null;
  return ErrorReportSender(
    queue: reporting.queue,
    api: ref.watch(clientErrorsApiProvider),
    withSession: () => ref.read(sessionProvider) is SessionActive,
    appVersion: reporting.device.appVersion,
  );
}, name: 'errorReportSender');
