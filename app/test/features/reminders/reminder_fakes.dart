import 'package:milionchik/features/reminders/reminder_notifications.dart';
import 'package:shared/shared.dart';
import 'package:timezone/timezone.dart' as tz;

final class FakeReminderNotifications implements ReminderNotifications {
  FakeReminderNotifications({
    this.zone = 'Europe/Moscow',
    this.allowed = true,
    this.grant = true,
    this.launch,
    this.settingsOpen = true,
    this.now,
  });

  String zone;
  bool allowed;
  bool grant;
  ReminderTap? launch;
  bool settingsOpen;
  DateTime Function()? now;
  Object? initError;
  Object? scheduleError;
  Object? cancelError;

  final Map<int, ReminderRequest> pending = {};
  final List<String> calls = [];
  ReminderTexts? texts;
  void Function(ReminderTap tap)? _onTap;

  List<LocalDate> get pendingDays =>
      (pending.values.map((r) => r.day).toList()..sort());

  void tap(int id, {String? payload}) =>
      _onTap!(ReminderTap(id: id, payload: payload ?? reminderLink.toString()));

  @override
  Future<ReminderTap?> initialize({
    required void Function(ReminderTap tap) onTap,
  }) async {
    calls.add('initialize');
    final error = initError;
    if (error != null) throw error;
    _onTap = onTap;
    return launch;
  }

  @override
  Future<String> localTimeZone() async => zone;

  @override
  Future<bool> areEnabled() async {
    calls.add('areEnabled');
    return allowed;
  }

  @override
  Future<bool> requestPermission() async {
    calls.add('requestPermission');
    if (grant) allowed = true;
    return grant;
  }

  @override
  Future<bool> openSettings() async {
    calls.add('openSettings');
    return settingsOpen;
  }

  @override
  Future<bool> schedule(ReminderRequest request, ReminderTexts texts) async {
    final error = scheduleError;
    if (error != null) throw error;
    final clock = now;
    if (clock != null &&
        !request.at.isAfter(tz.TZDateTime.from(clock(), tz.UTC))) {
      return false;
    }
    this.texts = texts;
    pending[request.id] = request;
    return true;
  }

  @override
  Future<void> cancel(int id) async {
    calls.add('cancel $id');
    final error = cancelError;
    if (error != null) throw error;
    pending.remove(id);
  }

  @override
  Future<void> cancelPending() async {
    calls.add('cancelPending');
    pending.clear();
  }

  @override
  Future<void> cancelAll() async {
    calls.add('cancelAll');
    final error = cancelError;
    if (error != null) throw error;
    pending.clear();
  }
}
