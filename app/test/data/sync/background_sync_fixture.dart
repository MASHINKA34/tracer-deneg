import 'package:milionchik/data/sync/background_sync.dart';

final class FakeScheduler implements BackgroundTaskScheduler {
  final List<String> calls = [];
  final List<BackgroundTaskRequest> scheduled = [];
  Object? failWith;

  @override
  Future<void> schedule(BackgroundTaskRequest request) async {
    calls.add('schedule ${request.uniqueName}');
    final error = failWith;
    if (error != null) throw error;
    scheduled.add(request);
  }

  @override
  Future<void> cancel(String uniqueName) async {
    calls.add('cancel $uniqueName');
    final error = failWith;
    if (error != null) throw error;
  }
}
