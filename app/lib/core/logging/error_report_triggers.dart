import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:shared/logging.dart';

import '../network_status.dart';
import 'error_report_sender.dart';
import 'error_reporting.dart';

final _log = Logger('errors');

class ErrorReportTriggersScope extends ConsumerStatefulWidget {
  const ErrorReportTriggersScope({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<ErrorReportTriggersScope> createState() =>
      _ErrorReportTriggersScopeState();
}

class _ErrorReportTriggersScopeState
    extends ConsumerState<ErrorReportTriggersScope> {
  ErrorReportSender? _sender;
  StreamSubscription<List<ConnectivityResult>>? _network;
  bool? _online;

  @override
  void initState() {
    super.initState();
    final sender = ref.read(errorReportSenderProvider);
    if (sender == null) {
      _log.fine('error report sending off: no report queue in this scope');
      return;
    }
    _sender = sender;
    _fire('start');
    try {
      _network = ref
          .read(networkChangesProvider)
          .listen(_onNetwork, onError: _onNetworkError);
      _log.info(
        'network status subscribed → queued error reports are also sent '
        'when network appears',
      );
    } catch (e, st) {
      _onNetworkError(e, st);
    }
  }

  void _onNetwork(List<ConnectivityResult> results) {
    final online = isOnline(results);
    final was = _online;
    _online = online;
    final types = results.map((r) => r.name).join(',');
    if (was == null) {
      _log.fine('network status online=$online types=$types (first event)');
      return;
    }
    if (online == was) {
      _log.fine('network changed types=$types, still online=$online');
      return;
    }
    if (!online) {
      _log.info('network lost types=$types → reports wait for network');
      return;
    }
    _log.info('network appeared types=$types → sending queued error reports');
    _fire('network');
  }

  void _onNetworkError(Object error, StackTrace stack) {
    _log.warning(
      'network status unavailable → queued error reports are sent only on '
      'start: ${describeError(error)}',
      error,
      stack,
    );
  }

  void _fire(String reason) {
    final sender = _sender;
    if (sender == null) return;
    unawaited(
      sender
          .send(reason)
          .then<void>(
            (_) {},
            onError: (Object e, StackTrace st) {
              _log.severe(
                'error reports send (reason=$reason) crashed: '
                '${describeError(e)}',
                e,
                st,
              );
            },
          ),
    );
  }

  @override
  void dispose() {
    final network = _network;
    if (network != null) {
      _log.info(
        'network status subscription cancelled (last online=${_online ?? '-'})'
        ' → no more error report sends on network changes',
      );
      unawaited(network.cancel());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
