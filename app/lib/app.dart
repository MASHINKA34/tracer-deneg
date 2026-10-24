import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import 'core/auth_gate.dart';
import 'core/clock.dart';
import 'core/router.dart';
import 'core/system_ui.dart';
import 'data/holiday_settings.dart';
import 'data/session/session_providers.dart';
import 'data/session/session_state.dart';
import 'features/auth/recovery_code_state.dart';
import 'features/auth/session_end_service.dart';
import 'features/expense/expense_snackbar_layer.dart';
import 'features/holidays/mood_controller.dart';
import 'features/profile/theme_mode.dart';
import 'l10n/app_localizations.dart';
import 'ui/theme/app_theme.dart';

final _log = Logger('app');

/// Корневой виджет: русская локаль, тема дизайн-системы (светлая/тёмная —
/// из настроек), настроение — по сегодняшней дате, прозрачные системные
/// панели, go_router.
class MilionchikApp extends ConsumerStatefulWidget {
  const MilionchikApp({super.key, this.today});

  /// «Сегодня» для настроения (тесты); по умолчанию — из [clockProvider].
  final LocalDate? today;

  @override
  ConsumerState<MilionchikApp> createState() => _MilionchikAppState();
}

class _MilionchikAppState extends ConsumerState<MilionchikApp> {
  late final ValueNotifier<SessionState> _session = ValueNotifier(
    ref.read(sessionProvider),
  );
  late final ValueNotifier<bool> _recoveryCodePending = ValueNotifier(
    ref.read(pendingRecoveryCodeProvider) != null,
  );
  late final GoRouter _router = buildRouter(
    auth: AuthGate(
      session: () => _session.value,
      changes: Listenable.merge([_session, _recoveryCodePending]),
      signInRequired: ref.read(signInRequiredProvider),
      recoveryCodePending: () => _recoveryCodePending.value,
    ),
  );
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () => ref.read(moodControllerProvider.notifier).resumed(),
    );
    ref.listenManual(sessionProvider, (previous, next) {
      _log.fine(
        'session ${previous?.name ?? '-'} → ${next.name}: re-checking sign-in '
        'redirect',
      );
      _session.value = next;
      if (next is SessionEnded && previous is! SessionEnded) {
        unawaited(ref.read(sessionEndServiceProvider).reportEnded(next));
      }
    });
    ref.listenManual(pendingRecoveryCodeProvider, (previous, next) {
      _log.fine(
        'recovery code ${previous == null ? 'none' : 'pending'} → '
        '${next == null ? 'none' : 'pending'}: re-checking sign-in redirect',
      );
      _recoveryCodePending.value = next != null;
    });
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _router.dispose();
    _session.dispose();
    _recoveryCodePending.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final today = widget.today;
    final mood = today == null
        ? ref.watch(moodControllerProvider.select((m) => m.mood))
        : moodOn(today, ref.watch(holidaySettingsProvider));
    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      locale: const Locale('ru'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      theme: AppTheme.build(Brightness.light, mood),
      darkTheme: AppTheme.build(Brightness.dark, mood),
      themeMode: ref.watch(themeModeProvider),
      themeAnimationDuration: AppTheme.transition,
      routerConfig: _router,
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: systemUiStyleFor(Theme.of(context).brightness),
        child: ExpenseSnackbarLayer(child: child ?? const SizedBox.shrink()),
      ),
    );
  }
}
