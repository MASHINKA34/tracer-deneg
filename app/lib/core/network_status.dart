import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

bool isOnline(List<ConnectivityResult> results) =>
    results.any((r) => r != ConnectivityResult.none);

final networkChangesProvider = Provider<Stream<List<ConnectivityResult>>>(
  (ref) => Connectivity().onConnectivityChanged,
  name: 'networkChanges',
);

final networkCheckProvider =
    Provider<Future<List<ConnectivityResult>> Function()>(
      (ref) => Connectivity().checkConnectivity,
      name: 'networkCheck',
    );
