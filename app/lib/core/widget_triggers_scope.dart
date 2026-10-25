import 'dart:async';

import 'package:drift/drift.dart' show TableUpdate;
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import '../data/providers.dart';
import '../data/session/session_providers.dart';
import '../data/session/session_state.dart';
import '../data/sync/sync_engine.dart';
import '../features/holidays/mood_controller.dart';
import '../features/profile/theme_mode.dart';
import '../features/widget/widget_updater.dart';

final _log = Logger('widget');

class WidgetTriggersScope extends ConsumerStatefulWidget {
  const WidgetTriggersScope({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<WidgetTriggersScope> createState() =>
      _WidgetTriggersScopeState();
}

class _WidgetTriggersScopeState extends ConsumerState<WidgetTriggersScope>
    with WidgetsBindingObserver {
  late final WidgetUpdater _updater = ref.read(widgetUpdaterProvider);
  StreamSubscription<Set<TableUpdate>>? _expenses;
  StreamSubscription<SyncEngineState>? _sync;
  DateTime? _lastSyncAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ref.listenManual<MoodToday>(moodControllerProvider, _moodChanged);
    ref.listenManual<ThemeMode>(themeModeProvider, (previous, next) {
      if (previous == next) return;
      _updater.request(WidgetUpdateSource.theme);
    });
    ref.listenManual<AsyncValue<String?>>(selectedBudgetIdProvider, (
      previous,
      next,
    ) {
      if (!next.hasValue) return;
      if (previous != null && previous.hasValue) {
        if (previous.value == next.value) return;
      }
      _updater.request(WidgetUpdateSource.budget);
    });
    ref.listenManual<SessionState>(sessionProvider, (previous, next) {
      if (previous?.name == next.name && previous?.userId == next.userId) {
        return;
      }
      _updater.request(WidgetUpdateSource.session);
    });
    try {
      _expenses = ref
          .read(widgetExpenseChangesProvider)
          .listen(
            (_) => _updater.request(WidgetUpdateSource.expenses),
            onError: (Object e, StackTrace st) =>
                _streamFailed('expense changes', e, st),
          );
    } catch (e, st) {
      _streamFailed('expense changes', e, st);
    }
    try {
      _sync = ref
          .read(syncEngineProvider)
          .states
          .listen(
            _syncChanged,
            onError: (Object e, StackTrace st) =>
                _streamFailed('sync states', e, st),
          );
    } catch (e, st) {
      _streamFailed('sync states', e, st);
    }
    _log.fine(
      'widget triggers mounted expenseWatch=${_expenses != null} '
      'syncWatch=${_sync != null} theme=${ref.read(themeModeProvider).name} '
      '→ widget update on startup',
    );
    _updater.request(WidgetUpdateSource.startup);
  }

  void _moodChanged(MoodToday? previous, MoodToday next) {
    if (previous == null) return;
    if (previous.date != next.date) {
      _updater.request(WidgetUpdateSource.day);
      return;
    }
    if (previous.mood != next.mood ||
        previous.holiday?.key != next.holiday?.key) {
      _updater.request(WidgetUpdateSource.mood);
    }
  }

  void _syncChanged(SyncEngineState state) {
    final at = state.lastSyncAt;
    if (at == null || at == _lastSyncAt) return;
    _lastSyncAt = at;
    _updater.request(WidgetUpdateSource.sync);
  }

  @override
  void didChangePlatformBrightness() {
    final theme = ref.read(themeModeProvider);
    if (theme != ThemeMode.system) {
      _log.fine(
        'system theme changed, widget theme=${theme.name} → no widget redraw',
      );
      return;
    }
    _updater.request(WidgetUpdateSource.systemTheme);
  }

  void _streamFailed(String what, Object error, StackTrace stack) {
    _log.warning(
      'widget triggers: $what unavailable → the widget is not updated by it, '
      'the other triggers keep working: ${describeError(error)}',
      error,
      stack,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final expenses = _expenses;
    final sync = _sync;
    if (expenses != null) unawaited(expenses.cancel());
    if (sync != null) unawaited(sync.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
