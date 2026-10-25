import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';

import '../../core/router.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/components/fitting_text.dart';
import '../../ui/components/snackbar.dart';
import '../../ui/components/toggle.dart';
import '../../ui/icons/app_icon.dart';
import '../../ui/theme/app_text.dart';
import '../../ui/theme/app_theme.dart';
import '../../ui/tokens/tokens.g.dart';
import '../categories/categories_top_bar.dart';
import 'reminder_scheduler.dart';
import 'reminder_settings.dart';

final _log = Logger('reminders');

final _nav = Logger('nav');

class RemindersScreen extends ConsumerStatefulWidget {
  const RemindersScreen({super.key});

  @override
  ConsumerState<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends ConsumerState<RemindersScreen> {
  bool? _pendingOn;
  bool _pickingTime = false;
  bool _checking = false;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _log.fine('reminders screen opened ${ref.read(reminderSettingsProvider)}');
    _lifecycle = AppLifecycleListener(
      onResume: () => unawaited(_checkBlocked('app resumed on the screen')),
    );
    unawaited(_checkBlocked('screen opened'));
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _checkBlocked(String event) async {
    if (_checking || _pendingOn != null) return;
    if (!ref.read(reminderSettingsProvider).enabled) return;
    _checking = true;
    try {
      final settings = ref.read(reminderSettingsProvider.notifier);
      final allowed = await ref
          .read(reminderSchedulerProvider)
          .notificationsAllowed(event);
      if (allowed || !mounted) return;
      _log.info(
        'reminders on, but notifications are blocked in system settings '
        '($event) → switch off, snackbar with "open settings"',
      );
      final saved = await settings.setEnabled(
        false,
        why: 'notifications blocked in system settings',
      );
      if (!mounted) return;
      if (saved) {
        _showDenied();
      } else {
        _showSaveFailed();
      }
    } finally {
      _checking = false;
    }
  }

  Future<void> _toggle(bool on) async {
    if (_pendingOn != null) {
      _log.fine('reminders switch tap ignored: permission request open');
      return;
    }
    _log.fine('reminders switch tap → ${on ? 'on' : 'off'}');
    final settings = ref.read(reminderSettingsProvider.notifier);
    if (!on) {
      final saved = await settings.setEnabled(false, why: 'switch off');
      if (!saved && mounted) _showSaveFailed();
      return;
    }
    setState(() => _pendingOn = true);
    final granted = await ref
        .read(reminderSchedulerProvider)
        .requestPermission();
    if (!granted) {
      _log.info(
        'reminders stay off: notification permission denied → switch back '
        'off, snackbar with "open settings"',
      );
      if (!mounted) return;
      setState(() => _pendingOn = null);
      _showDenied();
      return;
    }
    final saved = await settings.setEnabled(
      true,
      why: 'switch on, notifications allowed',
    );
    if (!mounted) return;
    setState(() => _pendingOn = null);
    if (!saved) _showSaveFailed();
  }

  void _showDenied() {
    final l10n = AppLocalizations.of(context);
    final scheduler = ref.read(reminderSchedulerProvider);
    showAppSnackbar(
      context,
      text: l10n.remindersDenied,
      actionLabel: l10n.remindersOpenSettings,
      onAction: () => unawaited(_openSettings(scheduler)),
    );
  }

  Future<void> _openSettings(ReminderScheduler scheduler) async {
    _log.fine('reminders snackbar "open settings" tap → system settings');
    final opened = await scheduler.openSettings();
    if (opened || !mounted) return;
    showAppSnackbar(
      context,
      text: AppLocalizations.of(context).remindersOpenSettingsFailed,
    );
  }

  void _showSaveFailed() => showAppSnackbar(
    context,
    text: AppLocalizations.of(context).remindersSaveFailed,
  );

  Future<void> _pickTime() async {
    if (_pickingTime) {
      _log.fine('reminders time tap ignored: time picker already open');
      return;
    }
    _pickingTime = true;
    try {
      final settings = ref.read(reminderSettingsProvider.notifier);
      final current = ref.read(reminderSettingsProvider).time;
      _log.fine('reminders time tap → time picker from $current');
      final picked = await showTimePicker(
        context: context,
        initialTime: TimeOfDay(hour: current.hour, minute: current.minute),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child ?? const SizedBox.shrink(),
        ),
      );
      if (picked == null) {
        _log.fine('time picker closed without a choice, keeping $current');
        return;
      }
      final saved = await settings.setTime(
        ReminderTime(picked.hour, picked.minute),
      );
      if (!saved && mounted) _showSaveFailed();
    } finally {
      _pickingTime = false;
    }
  }

  void _back() {
    if (context.canPop()) {
      _nav.fine('reminders closed by back button');
      context.pop();
      return;
    }
    _nav.fine('reminders closed with nothing under it → ${AppRoutes.profile}');
    context.go(AppRoutes.profile);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final settings = ref.watch(reminderSettingsProvider);
    return Scaffold(
      backgroundColor: colors.bgApp,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SafeArea(
            bottom: false,
            child: CategoriesTopBar(title: l10n.remindersTitle, onBack: _back),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                12,
                4,
                12,
                16 + MediaQuery.paddingOf(context).bottom,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Material(
                    color: colors.bgSurface,
                    borderRadius: BorderRadius.circular(RadiusTokens.lg),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _SwitchRow(
                          value: _pendingOn ?? settings.enabled,
                          onChanged: _toggle,
                        ),
                        _TimeRow(time: settings.time, onTap: _pickTime),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.remindersNote,
                    style: AppText.caption.copyWith(color: colors.textTertiary),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    return MergeSemantics(
      child: InkWell(
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 14, 0),
          child: Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FittingText(
                        l10n.remindersSwitchTitle,
                        style: AppText.bodyL.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      FittingText(
                        l10n.remindersSwitchHint,
                        style: AppText.caption.copyWith(
                          color: colors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              AppToggle(value: value, onChanged: onChanged),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimeRow extends StatelessWidget {
  const _TimeRow({required this.time, required this.onTap});

  final ReminderTime time;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    return MergeSemantics(
      child: Semantics(
        button: true,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 14, 4),
            child: Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: FittingText(
                      l10n.remindersTime,
                      style: AppText.bodyL.copyWith(color: colors.textPrimary),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '$time',
                  maxLines: 1,
                  style: AppText.labelM.copyWith(color: colors.textPrimary),
                ),
                const SizedBox(width: 12),
                AppIcon(
                  AppIcons.chevronRight,
                  size: 18,
                  color: colors.textTertiary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
