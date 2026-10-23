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
import 'data/session/session_providers.dart';
import 'data/session/session_state.dart';
import 'features/auth/recovery_code_state.dart';
import 'features/auth/session_end_service.dart';
import 'features/expense/expense_snackbar_layer.dart';
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
  LocalDate? _moodDay;
  late Mood _mood;

  /// Настроение на сегодня (00-spec §7.6.3). Настроек праздников ещё нет
  /// (этап 13) — берём настройки по умолчанию: все праздники включены.
  Mood _moodToday(LocalDate today) {
    final mood = moodOn(today, const HolidaySettings());
    _log.info('mood=${mood.name} today=$today (holiday settings: defaults)');
    return mood;
  }

  @override
  void initState() {
    super.initState();
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
    _router.dispose();
    _session.dispose();
    _recoveryCodePending.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final today = widget.today ?? ref.watch(clockProvider).today();
    if (today != _moodDay) {
      _moodDay = today;
      _mood = _moodToday(today);
    }
    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      locale: const Locale('ru'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      theme: AppTheme.build(Brightness.light, _mood),
      darkTheme: AppTheme.build(Brightness.dark, _mood),
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
