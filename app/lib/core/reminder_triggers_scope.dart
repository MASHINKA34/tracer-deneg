import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import '../data/providers.dart';
import '../data/repositories/expenses_repository.dart';
import '../data/session/session_providers.dart';
import '../data/session/session_state.dart';
import '../features/reminders/reminder_scheduler.dart';
import '../features/reminders/reminder_settings.dart';

final _log = Logger('reminders');

class ReminderTriggersScope extends ConsumerStatefulWidget {
  const ReminderTriggersScope({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<ReminderTriggersScope> createState() =>
      _ReminderTriggersScopeState();
}

class _ReminderTriggersScopeState extends ConsumerState<ReminderTriggersScope> {
  late final ReminderScheduler _scheduler = ref.read(reminderSchedulerProvider);
  late final AppLifecycleListener _lifecycle;
  late final StreamSubscription<TodayExpenseSaved> _today;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () => unawaited(_scheduler.refreshIfStale('app resumed')),
    );
    ref.listenManual<ReminderSettings>(reminderSettingsProvider, (
      previous,
      next,
    ) {
      if (previous == next) return;
      unawaited(
        _scheduler.reschedule('settings changed ${previous ?? '-'} → $next'),
      );
    });
    ref.listenManual<SessionState>(sessionProvider, (previous, next) {
      if (next is! SessionActive || previous is SessionActive) return;
      unawaited(
        _scheduler.reschedule(
          'signed in ${previous?.name ?? '-'}→${next.name}',
        ),
      );
    });
    _today = ref
        .read(todayExpenseEventsProvider)
        .stream
        .listen(
          (event) => unawaited(
            _scheduler.cancelToday('expense saved for today: $event'),
          ),
          onError: (Object e, StackTrace st) => _log.warning(
            'today expense events failed → today\'s reminder is not cancelled '
            'by new expenses until restart: ${describeError(e)}',
            e,
            st,
          ),
        );
    _log.fine(
      'reminder triggers mounted ${ref.read(reminderSettingsProvider)} → '
      'planning on startup',
    );
    unawaited(_scheduler.start());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    unawaited(_today.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
