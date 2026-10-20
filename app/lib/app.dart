import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import 'core/router.dart';
import 'core/system_ui.dart';
import 'l10n/app_localizations.dart';
import 'ui/theme/app_theme.dart';

final _log = Logger('app');

/// Корневой виджет: русская локаль, тема дизайн-системы (светлая/тёмная —
/// как в системе), настроение — по сегодняшней дате, прозрачные системные
/// панели, go_router.
class MilionchikApp extends StatefulWidget {
  const MilionchikApp({super.key, this.today});

  /// «Сегодня» для настроения (тесты); по умолчанию — дата телефона.
  final LocalDate? today;

  @override
  State<MilionchikApp> createState() => _MilionchikAppState();
}

class _MilionchikAppState extends State<MilionchikApp> {
  late final GoRouter _router = buildRouter();
  late final Mood _mood = _moodToday();

  /// Настроение на сегодня (00-spec §7.6.3). Настроек праздников ещё нет
  /// (этап 13) — берём настройки по умолчанию: все праздники включены.
  Mood _moodToday() {
    final today = widget.today ?? LocalDate.fromDateTime(DateTime.now());
    final mood = moodOn(today, const HolidaySettings());
    _log.info('mood=${mood.name} today=$today (holiday settings: defaults)');
    return mood;
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      locale: const Locale('ru'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      theme: AppTheme.build(Brightness.light, _mood),
      darkTheme: AppTheme.build(Brightness.dark, _mood),
      themeAnimationDuration: AppTheme.transition,
      routerConfig: _router,
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: systemUiStyleFor(Theme.of(context).brightness),
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}
