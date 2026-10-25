import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared/shared.dart' show LocalDate;
import 'package:timezone/timezone.dart' as tz;

import '../../core/router.dart';

const String reminderChannelId = 'reminders';

const String reminderSmallIcon = 'ic_stat_reminder';

final Uri reminderLink = Uri(
  scheme: AppRoutes.deepLinkScheme,
  host: AppRoutes.addDeepLinkHost,
);

final class ReminderTexts {
  const ReminderTexts({
    required this.title,
    required this.body,
    required this.channelName,
    required this.channelDescription,
  });

  final String title;
  final String body;
  final String channelName;
  final String channelDescription;
}

final class ReminderRequest {
  const ReminderRequest({
    required this.id,
    required this.day,
    required this.at,
  });

  final int id;
  final LocalDate day;
  final tz.TZDateTime at;

  @override
  String toString() => 'ReminderRequest(id=$id day=$day at=$at)';
}

final class ReminderTap {
  const ReminderTap({required this.id, required this.payload});

  final int? id;
  final String? payload;
}

abstract interface class ReminderNotifications {
  Future<ReminderTap?> initialize({
    required void Function(ReminderTap tap) onTap,
  });

  Future<String> localTimeZone();

  Future<bool> areEnabled();

  Future<bool> requestPermission();

  Future<bool> openSettings();

  Future<bool> schedule(ReminderRequest request, ReminderTexts texts);

  Future<void> cancel(int id);

  Future<void> cancelPending();

  Future<void> cancelAll();
}

final class PluginReminderNotifications implements ReminderNotifications {
  PluginReminderNotifications([FlutterLocalNotificationsPlugin? plugin])
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  AndroidFlutterLocalNotificationsPlugin get _android {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) {
      throw UnsupportedError('reminders work only on Android');
    }
    return android;
  }

  @override
  Future<ReminderTap?> initialize({
    required void Function(ReminderTap tap) onTap,
  }) async {
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings(reminderSmallIcon),
      ),
      onDidReceiveNotificationResponse: (response) =>
          onTap(ReminderTap(id: response.id, payload: response.payload)),
    );
    final launch = await _plugin.getNotificationAppLaunchDetails();
    final response = launch?.notificationResponse;
    if (launch == null || !launch.didNotificationLaunchApp) return null;
    return ReminderTap(id: response?.id, payload: response?.payload);
  }

  @override
  Future<String> localTimeZone() async =>
      (await FlutterTimezone.getLocalTimezone()).identifier;

  @override
  Future<bool> areEnabled() async =>
      await _android.areNotificationsEnabled() ?? false;

  @override
  Future<bool> requestPermission() async =>
      await _android.requestNotificationsPermission() ?? false;

  @override
  Future<bool> openSettings() async =>
      await _android.openAppNotificationSettings() ?? false;

  @override
  Future<bool> schedule(ReminderRequest request, ReminderTexts texts) async {
    if (!request.at.isAfter(tz.TZDateTime.now(request.at.location))) {
      return false;
    }
    await _plugin.zonedSchedule(
      id: request.id,
      scheduledDate: request.at,
      title: texts.title,
      body: texts.body,
      payload: reminderLink.toString(),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          reminderChannelId,
          texts.channelName,
          channelDescription: texts.channelDescription,
          icon: reminderSmallIcon,
          category: AndroidNotificationCategory.reminder,
        ),
      ),
    );
    return true;
  }

  @override
  Future<void> cancel(int id) => _plugin.cancel(id: id);

  @override
  Future<void> cancelPending() => _plugin.cancelAllPendingNotifications();

  @override
  Future<void> cancelAll() => _plugin.cancelAll();
}

final reminderNotificationsProvider = Provider<ReminderNotifications>(
  (ref) => PluginReminderNotifications(),
  name: 'reminderNotifications',
);
