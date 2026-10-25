import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/data/db/app_database.dart';
import 'package:milionchik/data/providers.dart';
import 'package:milionchik/data/repositories/account_data_cleaner.dart';
import 'package:milionchik/data/repositories/prefs_repository.dart';
import 'package:milionchik/features/reminders/reminder_settings.dart';

import '../../data/api/fake_api_adapter.dart' show LogCapture;

final class _BrokenPrefs implements PrefsRepository {
  _BrokenPrefs(this._inner);

  final PrefsRepository _inner;

  @override
  Future<void> setBool(String key, bool value) async =>
      throw StateError('disk I/O error (test)');

  @override
  Future<void> setInt(String key, int value) async =>
      throw StateError('disk I/O error (test)');

  @override
  Future<String?> getString(String key) => _inner.getString(key);

  @override
  Future<int?> getInt(String key) => _inner.getInt(key);

  @override
  Future<bool?> getBool(String key) =>
      Future.error(StateError('database is locked (test)'));

  @override
  Stream<String?> watchString(String key) => _inner.watchString(key);

  @override
  Stream<int?> watchInt(String key) => _inner.watchInt(key);

  @override
  Stream<bool?> watchBool(String key) => _inner.watchBool(key);

  @override
  Future<void> setString(String key, String value) =>
      _inner.setString(key, value);

  @override
  Future<void> remove(String key) => _inner.remove(key);

  @override
  Future<String> putStringIfAbsent(String key, String Function() create) =>
      _inner.putStringIfAbsent(key, create);
}

void main() {
  late AppDatabase db;
  late DriftPrefsRepository prefs;
  late LogCapture logs;

  setUp(() {
    logs = LogCapture();
    db = AppDatabase.memory();
    prefs = DriftPrefsRepository(db);
  });

  tearDown(() async {
    await db.close();
    await logs.dispose();
  });

  Iterable<String> lines([Level from = Level.ALL]) => logs.records
      .where((r) => r.loggerName == 'reminders' && r.level >= from)
      .map((r) => r.message);

  test('не включали ни разу - выключены, 21:00', () async {
    final settings = await loadReminderSettings(prefs);

    expect(settings, ReminderSettings.standard);
    expect(settings.enabled, isFalse);
    expect(settings.time, const ReminderTime(21, 0));
    expect(
      lines(Level.INFO).single,
      matches(
        r'^reminder settings off time=21:00 \(never switched, default time\) '
        r'in \d+ms$',
      ),
    );
  });

  test('сохранённые вкл и 07:30 читаются при старте', () async {
    await prefs.setBool(PrefKeys.remindersEnabled, true);
    await prefs.setInt(PrefKeys.reminderMinutes, 450);

    final settings = await loadReminderSettings(prefs);

    expect(
      settings,
      const ReminderSettings(enabled: true, time: ReminderTime(7, 30)),
    );
    expect(
      lines(Level.INFO).single,
      contains(
        'on time=07:30 (from key=remindersEnabled, time from '
        'key=reminderMinutes)',
      ),
    );
  });

  test(
    'минуты вне суток - warn и 21:00; чтение упало - warn и выключены',
    () async {
      await prefs.setInt(PrefKeys.reminderMinutes, 1440);

      expect((await loadReminderSettings(prefs)).time, ReminderTime.standard);
      expect(
        lines(Level.WARNING).single,
        'reminder time ignored: key=reminderMinutes is out of range '
        'minutes=1440, using 21:00',
      );

      final broken = await loadReminderSettings(_BrokenPrefs(prefs));
      expect(broken, ReminderSettings.standard);
      final warning = logs.records.lastWhere(
        (r) => r.loggerName == 'reminders' && r.level == Level.WARNING,
      );
      expect(warning.message, contains('reminder settings read failed after'));
      expect(warning.message, contains('database is locked (test)'));
      expect(warning.stackTrace, isNotNull);
    },
  );

  test(
    'переключатель и время пишутся в local_prefs и меняют состояние',
    () async {
      final container = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);
      final controller = container.read(reminderSettingsProvider.notifier);

      expect(await controller.setEnabled(true, why: 'test'), isTrue);
      expect(await controller.setTime(const ReminderTime(22, 15)), isTrue);

      expect(
        container.read(reminderSettingsProvider),
        const ReminderSettings(enabled: true, time: ReminderTime(22, 15)),
      );
      expect(await prefs.getBool(PrefKeys.remindersEnabled), isTrue);
      expect(await prefs.getInt(PrefKeys.reminderMinutes), 1335);
      expect(
        lines(Level.INFO).last,
        matches(
          r'^reminders settings changed to on time=22:15 previous=on '
          r'time=21:00 \(time picked\) in \d+ms$',
        ),
      );
    },
  );

  test(
    'запись не удалась - false, состояние прежнее, warn с ошибкой',
    () async {
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          prefsRepositoryProvider.overrideWithValue(_BrokenPrefs(prefs)),
        ],
      );
      addTearDown(container.dispose);

      final saved = await container
          .read(reminderSettingsProvider.notifier)
          .setEnabled(true, why: 'switch on');

      expect(saved, isFalse);
      expect(
        container.read(reminderSettingsProvider),
        ReminderSettings.standard,
      );
      final warning = logs.records.singleWhere(
        (r) => r.loggerName == 'reminders' && r.level == Level.WARNING,
      );
      expect(
        warning.message,
        allOf(
          startsWith('reminders on time=21:00 not saved after '),
          contains('(switch on), keeping off time=21:00'),
          contains('disk I/O error (test)'),
        ),
      );
    },
  );

  test(
    'напоминания - настройка телефона: выход из аккаунта их не стирает',
    () async {
      await prefs.setBool(PrefKeys.remindersEnabled, true);
      await prefs.setInt(PrefKeys.reminderMinutes, 1290);
      await prefs.setString(PrefKeys.selectedBudgetId, 'budget-1');

      final removal = await DriftAccountDataCleaner(db)
          .clearAccountData('test');

      expect(PrefKeys.phoneSettings, contains(PrefKeys.remindersEnabled));
      expect(PrefKeys.phoneSettings, contains(PrefKeys.reminderMinutes));
      expect(
        removal.keptPrefs,
        containsAll([PrefKeys.reminderMinutes, PrefKeys.remindersEnabled]),
      );
      expect(await prefs.getBool(PrefKeys.remindersEnabled), isTrue);
      expect(await prefs.getInt(PrefKeys.reminderMinutes), 1290);
      expect(await prefs.getString(PrefKeys.selectedBudgetId), isNull);
    },
  );
}
