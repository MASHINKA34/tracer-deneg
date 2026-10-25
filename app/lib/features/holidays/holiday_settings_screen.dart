import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import '../../core/router.dart';
import '../../data/holiday_settings.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/components/category_badge.dart';
import '../../ui/components/fitting_text.dart';
import '../../ui/components/snackbar.dart';
import '../../ui/components/toggle.dart';
import '../../ui/icons/app_icon.dart';
import '../../ui/theme/app_text.dart';
import '../../ui/theme/app_theme.dart';
import '../categories/categories_top_bar.dart';
import '../profile/profile_budgets.dart' show ProfileCard;
import 'birthday_sheet.dart';

final _log = Logger('holidays');

final _nav = Logger('nav');

String holidayTitle(AppLocalizations l10n, HolidayKey key) => switch (key) {
  HolidayKey.newyear => l10n.holidayNewyear,
  HolidayKey.valentine => l10n.holidayValentine,
  HolidayKey.defender => l10n.holidayDefender,
  HolidayKey.maslenitsa => l10n.holidayMaslenitsa,
  HolidayKey.women => l10n.holidayWomen,
  HolidayKey.labour => l10n.holidayLabour,
  HolidayKey.victory => l10n.holidayVictory,
  HolidayKey.children => l10n.holidayChildren,
  HolidayKey.knowledge => l10n.holidayKnowledge,
  HolidayKey.halloween => l10n.holidayHalloween,
  HolidayKey.birthday => l10n.holidayBirthdays,
};

String holidayPeriod(AppLocalizations l10n, HolidayKey key) => switch (key) {
  HolidayKey.newyear => l10n.holidayNewyearPeriod,
  HolidayKey.valentine => l10n.holidayValentinePeriod,
  HolidayKey.defender => l10n.holidayDefenderPeriod,
  HolidayKey.maslenitsa => l10n.holidayMaslenitsaPeriod,
  HolidayKey.women => l10n.holidayWomenPeriod,
  HolidayKey.labour => l10n.holidayLabourPeriod,
  HolidayKey.victory => l10n.holidayVictoryPeriod,
  HolidayKey.children => l10n.holidayChildrenPeriod,
  HolidayKey.knowledge => l10n.holidayKnowledgePeriod,
  HolidayKey.halloween => l10n.holidayHalloweenPeriod,
  HolidayKey.birthday => l10n.holidayBirthdaysPeriod,
};

class HolidaySettingsScreen extends ConsumerStatefulWidget {
  const HolidaySettingsScreen({super.key});

  @override
  ConsumerState<HolidaySettingsScreen> createState() =>
      _HolidaySettingsScreenState();
}

class _HolidaySettingsScreenState extends ConsumerState<HolidaySettingsScreen> {
  bool _pickingBirthday = false;

  @override
  void initState() {
    super.initState();
    _log.fine(
      'holiday settings screen opened ${ref.read(holidaySettingsProvider)}',
    );
  }

  AccountHolidaySettings get _settings =>
      ref.read(accountHolidaySettingsProvider.notifier);

  Future<void> _apply(String what, Future<bool> Function() change) async {
    _log.fine('holiday settings tap: $what');
    final saved = await change();
    if (saved || !mounted) return;
    showAppSnackbar(
      context,
      text: AppLocalizations.of(context).holidaysSaveFailed,
    );
  }

  Future<void> _pickBirthday() async {
    if (_pickingBirthday) {
      _log.fine('holiday settings birthday tap ignored: sheet already open');
      return;
    }
    _pickingBirthday = true;
    try {
      final current = ref.read(holidaySettingsProvider).birthday;
      final choice = await showBirthdaySheet(context, initial: current);
      if (!mounted) return;
      switch (choice) {
        case null:
          return;
        case BirthdayPicked(:final birthday):
          if (birthday == current) {
            _log.fine('holiday settings birthday: same date chosen, no change');
            return;
          }
          await _apply('birthday', () => _settings.setBirthday(birthday));
        case BirthdayCleared():
          await _apply('birthday clear', () => _settings.setBirthday(null));
      }
    } finally {
      _pickingBirthday = false;
    }
  }

  void _back() {
    if (context.canPop()) {
      _nav.fine('holiday settings closed by back button');
      context.pop();
      return;
    }
    _nav.fine(
      'holiday settings closed with nothing under it → ${AppRoutes.profile}',
    );
    context.go(AppRoutes.profile);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final mood = context.mood;
    final settings = ref.watch(holidaySettingsProvider);
    final birthday = settings.birthday;
    return Scaffold(
      backgroundColor: colors.bgApp,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SafeArea(
            bottom: false,
            child: CategoriesTopBar(title: l10n.holidaysTitle, onBack: _back),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                12,
                4,
                12,
                24 + MediaQuery.paddingOf(context).bottom,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ProfileCard(
                    children: [
                      _ToggleRow(
                        title: l10n.holidaysMasterTitle,
                        titleStyle: AppText.labelL,
                        subtitle: l10n.holidaysMasterHint,
                        value: settings.enabled,
                        onChanged: (on) => _apply(
                          'all holidays ${on ? 'on' : 'off'}',
                          () => _settings.setEnabled(on),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ProfileCard(
                    children: [
                      _BirthdayRow(
                        value: birthday == null
                            ? l10n.holidaysBirthdayNone
                            : birthdayText(birthday),
                        badge: mood.soft,
                        onTap: _pickBirthday,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.holidaysBirthdayVisible,
                    style: AppText.caption.copyWith(color: colors.textTertiary),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
                    child: Semantics(
                      header: true,
                      child: FittingText(
                        l10n.holidaysListTitle,
                        style: AppText.titleS.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ProfileCard(
                    children: [
                      for (final key in HolidayKey.values)
                        _ToggleRow(
                          leading: CategoryBadge(
                            emoji: key.emoji,
                            color: null,
                            background: colors.bgSurface2,
                          ),
                          title: holidayTitle(l10n, key),
                          titleStyle: AppText.labelM,
                          subtitle: holidayPeriod(l10n, key),
                          value: !settings.disabled.contains(key),
                          onChanged: (on) => _apply(
                            '${key.name} ${on ? 'on' : 'off'}',
                            () => _settings.setHoliday(key, on),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.holidaysNote,
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

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    this.leading,
    required this.title,
    required this.titleStyle,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final Widget? leading;
  final String title;
  final TextStyle titleStyle;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final leading = this.leading;
    return MergeSemantics(
      child: InkWell(
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              if (leading != null) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: leading,
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: _Texts(
                    title: title,
                    titleStyle: titleStyle.copyWith(color: colors.textPrimary),
                    subtitle: subtitle,
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

class _Texts extends StatelessWidget {
  const _Texts({
    required this.title,
    required this.titleStyle,
    required this.subtitle,
  });

  final String title;
  final TextStyle titleStyle;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      FittingText(title, style: titleStyle),
      const SizedBox(height: 2),
      FittingText(
        subtitle,
        style: AppText.caption.copyWith(color: context.colors.textTertiary),
      ),
    ],
  );
}

class _BirthdayRow extends StatelessWidget {
  const _BirthdayRow({
    required this.value,
    required this.badge,
    required this.onTap,
  });

  final String value;
  final Color badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final texts = _Texts(
      title: l10n.holidaysBirthdayTitle,
      titleStyle: AppText.labelM.copyWith(color: colors.textPrimary),
      subtitle: l10n.holidaysBirthdayHint,
    );
    final valueStyle = AppText.bodyM.copyWith(color: colors.textTertiary);
    return MergeSemantics(
      child: Semantics(
        button: true,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                CategoryBadge(
                  emoji: HolidayKey.birthday.emoji,
                  color: null,
                  background: badge,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final valueWidth = FittingText.widestWord(
                        context,
                        value.replaceAll(' ', ' '),
                        valueStyle,
                      );
                      final textsWidth = constraints.maxWidth - 12 - valueWidth;
                      final widest = [
                        FittingText.widestWord(
                          context,
                          l10n.holidaysBirthdayTitle,
                          AppText.labelM,
                        ),
                        FittingText.widestWord(
                          context,
                          l10n.holidaysBirthdayHint,
                          AppText.caption,
                        ),
                      ].reduce((a, b) => a > b ? a : b);
                      if (textsWidth >= widest) {
                        return Row(
                          children: [
                            Expanded(child: texts),
                            const SizedBox(width: 12),
                            Text(value, maxLines: 1, style: valueStyle),
                          ],
                        );
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          texts,
                          const SizedBox(height: 2),
                          FittingText(value, style: valueStyle),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(width: 12),
                AppIcon(
                  AppIcons.chevronRight,
                  size: 20,
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
