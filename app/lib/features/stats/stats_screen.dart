import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import '../../core/clock.dart';
import '../../core/router.dart';
import '../../data/db/redact_db_error.dart';
import '../../data/providers.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/components/chip.dart';
import '../../ui/components/fitting_text.dart';
import '../../ui/components/segmented.dart';
import '../../ui/components/stat_row.dart';
import '../../ui/components/tap_target.dart';
import '../../ui/icons/app_icon.dart';
import '../../ui/theme/app_text.dart';
import '../../ui/theme/app_theme.dart';
import '../../ui/tokens/tokens.g.dart';
import '../month/month_picker_sheet.dart';
import 'donut_chart.dart';
import 'stats_controller.dart';
import 'stats_month.dart';
import 'stats_year.dart';
import 'year_chart.dart';

final _log = Logger('stats');

enum StatsMode { month, year }

const List<String> _monthKeys = [
  'january',
  'february',
  'march',
  'april',
  'may',
  'june',
  'july',
  'august',
  'september',
  'october',
  'november',
  'december',
];

String statsPercent(int percent) => switch (percent) {
  < 0 => '$minusSign${-percent}%',
  > 0 => '+$percent%',
  _ => '0%',
};

class StatsScreen extends ConsumerStatefulWidget {
  const StatsScreen({super.key});

  @override
  ConsumerState<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends ConsumerState<StatsScreen> {
  Stopwatch _sw = Stopwatch()..start();
  bool _loading = true;
  bool _pickerOpen = false;
  ({String? budgetId, YearMonth month, int categories, int expenses})? _shown;
  final Set<String> _reportedUnknown = {};
  String? _failed;
  StatsMode _mode = StatsMode.month;
  Stopwatch _yearSw = Stopwatch()..start();
  bool _yearLoading = true;
  ({String? budgetId, int year, int months, int categories, int expenses})?
  _yearShown;
  String? _yearFailed;

  @override
  void initState() {
    super.initState();
    _log.fine(
      'stats screen opened month=${ref.read(statsMonthControllerProvider)} '
      'today=${ref.read(clockProvider).today()}',
    );
    ref.listenManual(statsMonthProvider, _onData, fireImmediately: true);
  }

  void _onData(AsyncValue<StatsMonth>? previous, AsyncValue<StatsMonth> next) {
    switch (next) {
      case AsyncData(value: final stats):
        _logBuilt(stats);
      case AsyncError(:final error, :final stackTrace):
        _logFailed(error, stackTrace);
      default:
        if (!_loading) {
          _loading = true;
          _sw = Stopwatch()..start();
        }
    }
  }

  void _logBuilt(StatsMonth stats) {
    final shown = (
      budgetId: stats.budgetId,
      month: stats.month,
      categories: stats.categories.length,
      expenses: stats.expenseCount,
    );
    _failed = null;
    final previous = _shown;
    if (previous == shown) return;
    _shown = shown;
    final period = '${stats.month.firstDay}..${stats.month.lastDay}';
    if (_loading ||
        previous == null ||
        previous.month != shown.month ||
        previous.budgetId != shown.budgetId) {
      _log.fine(
        'stats month built period=$period budgetId=${stats.budgetId ?? '-'} '
        'categories=${stats.categories.length} '
        'expenses=${stats.expenseCount} '
        'comparison=${stats.comparison == null ? 'none' : 'shown'}'
        '${stats.budgetId == null ? ': no budget selected, empty state' : ''}'
        '${stats.budgetId != null && stats.isEmpty ? ': no expenses, empty state' : ''}'
        ' in ${_sw.elapsedMilliseconds}ms',
      );
    } else {
      _log.fine(
        'stats month updated period=$period budgetId=${stats.budgetId} '
        'categories=${previous.categories} → ${shown.categories} '
        'expenses=${previous.expenses} → ${shown.expenses}',
      );
    }
    _loading = false;
    for (final id in stats.unknownCategoryIds) {
      if (!_reportedUnknown.add(id)) continue;
      _log.warning(
        'stats category=$id of budgetId=${stats.budgetId} month=${stats.month} '
        'not found among live categories, counted as system «other»',
      );
    }
  }

  void _logFailed(Object error, StackTrace stackTrace) {
    var what = 'data failed';
    var cause = error;
    while (true) {
      if (cause is ProviderException) {
        cause = cause.exception;
      } else if (cause is StatsDataError) {
        what = cause.what;
        cause = cause.cause;
      } else {
        break;
      }
    }
    final month = ref.read(statsMonthControllerProvider);
    final budget = ref.read(selectedBudgetIdProvider);
    final budgetId = budget.hasError ? 'unknown' : budget.value ?? '-';
    final failed = '$month $budgetId $what';
    if (failed == _failed) return;
    _failed = failed;
    _loading = false;
    _shown = null;
    final redacted = redactDbError(cause);
    _log.severe(
      'stats month failed month=$month budgetId=$budgetId: '
      '$what after ${_sw.elapsedMilliseconds}ms, showing error text: '
      '${describeError(redacted)}',
      redacted,
      stackTrace,
    );
  }

  Future<void> _openPicker(YearMonth month) async {
    if (_pickerOpen) {
      _log.fine('stats period chip tap month=$month ignored: picker open');
      return;
    }
    _pickerOpen = true;
    _log.fine('stats period chip tap month=$month → month picker');
    final container = ProviderScope.containerOf(context, listen: false);
    final YearMonth? chosen;
    try {
      chosen = await showMonthPickerSheet(context, shown: month);
    } finally {
      _pickerOpen = false;
    }
    if (chosen == null) return;
    container.read(statsMonthControllerProvider.notifier).open(chosen);
  }

  void _onMode(StatsMode mode) {
    if (mode == _mode) {
      _log.fine('stats mode ${mode.name} tapped: already shown');
      return;
    }
    final month = ref.read(statsMonthControllerProvider);
    if (mode == StatsMode.year) {
      _log.fine(
        'stats mode month → year by=segmented month=$month, '
        'opening its year ${month.year}',
      );
      ref
          .read(statsYearControllerProvider.notifier)
          .open(month.year, by: 'mode');
    } else {
      _log.fine(
        'stats mode year → month by=segmented '
        'year=${ref.read(statsYearControllerProvider)} month=$month',
      );
    }
    _yearShown = null;
    _yearFailed = null;
    _yearLoading = true;
    _yearSw = Stopwatch()..start();
    setState(() => _mode = mode);
  }

  void _onYearData(AsyncValue<StatsYear> value) {
    switch (value) {
      case AsyncData(value: final stats):
        _logYearBuilt(stats);
      case AsyncError(:final error, :final stackTrace):
        _logYearFailed(error, stackTrace);
      default:
        if (!_yearLoading) {
          _yearLoading = true;
          _yearSw = Stopwatch()..start();
        }
    }
  }

  void _logYearBuilt(StatsYear stats) {
    final shown = (
      budgetId: stats.budgetId,
      year: stats.year,
      months: stats.monthsWithSpending,
      categories: stats.categories.length,
      expenses: stats.expenseCount,
    );
    _yearFailed = null;
    final previous = _yearShown;
    if (previous == shown) return;
    _yearShown = shown;
    if (_yearLoading ||
        previous == null ||
        previous.year != shown.year ||
        previous.budgetId != shown.budgetId) {
      _log.fine(
        'stats year built year=${stats.year} '
        'budgetId=${stats.budgetId ?? '-'} '
        'monthsWithSpending=${stats.monthsWithSpending} '
        'priciest=${stats.priciest ?? '-'} '
        'categories=${stats.categories.length} '
        'expenses=${stats.expenseCount}'
        '${stats.budgetId == null ? ': no budget selected, empty state' : ''}'
        '${stats.budgetId != null && stats.isEmpty ? ': no expenses, empty state' : ''}'
        ' in ${_yearSw.elapsedMilliseconds}ms',
      );
    } else {
      _log.fine(
        'stats year updated year=${stats.year} budgetId=${stats.budgetId} '
        'monthsWithSpending=${previous.months} → ${shown.months} '
        'categories=${previous.categories} → ${shown.categories} '
        'expenses=${previous.expenses} → ${shown.expenses}',
      );
    }
    _yearLoading = false;
    for (final id in stats.unknownCategoryIds) {
      if (!_reportedUnknown.add(id)) continue;
      _log.warning(
        'stats category=$id of budgetId=${stats.budgetId} year=${stats.year} '
        'not found among live categories, counted as system «other»',
      );
    }
  }

  void _logYearFailed(Object error, StackTrace stackTrace) {
    var what = 'data failed';
    var cause = error;
    while (true) {
      if (cause is ProviderException) {
        cause = cause.exception;
      } else if (cause is StatsDataError) {
        what = cause.what;
        cause = cause.cause;
      } else {
        break;
      }
    }
    final year = ref.read(statsYearControllerProvider);
    final budget = ref.read(selectedBudgetIdProvider);
    final budgetId = budget.hasError ? 'unknown' : budget.value ?? '-';
    final failed = '$year $budgetId $what';
    if (failed == _yearFailed) return;
    _yearFailed = failed;
    _yearLoading = false;
    _yearShown = null;
    final redacted = redactDbError(cause);
    _log.severe(
      'stats year failed year=$year budgetId=$budgetId: '
      '$what after ${_yearSw.elapsedMilliseconds}ms, showing error text: '
      '${describeError(redacted)}',
      redacted,
      stackTrace,
    );
  }

  void _changeYear(int year, int delta) {
    ref
        .read(statsYearControllerProvider.notifier)
        .open(year + delta, by: 'arrow');
  }

  void _openYearCategory(StatsYear stats, StatsCategory category, int index) {
    final from = stats.from;
    final to = stats.to;
    _log.fine(
      'stats year category row #$index tap id=${category.id} '
      'year=${stats.year} → ${AppRoutes.search} filter category+period '
      '$from..$to',
    );
    context.push(
      AppRoutes.searchFor(categoryId: category.id, from: from, to: to),
    );
  }

  void _openCategory(StatsMonth stats, StatsCategory category, int index) {
    final from = stats.month.firstDay;
    final to = stats.month.lastDay;
    _log.fine(
      'stats category row #$index tap id=${category.id} month=${stats.month} '
      '→ ${AppRoutes.search} filter category+period $from..$to',
    );
    context.push(
      AppRoutes.searchFor(categoryId: category.id, from: from, to: to),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final month = ref.watch(statsMonthControllerProvider);
    final value = ref.watch(statsMonthProvider);
    final bottom = MediaQuery.paddingOf(context).bottom;

    final Widget period;
    final Widget content;
    if (_mode == StatsMode.year) {
      final year = ref.watch(statsYearControllerProvider);
      final today = ref.watch(clockProvider).today();
      final yearValue = ref.watch(statsYearProvider);
      _onYearData(yearValue);
      period = _YearPeriod(
        year: year,
        onPrevious: year > 1 ? () => _changeYear(year, -1) : null,
        onNext: year < today.year ? () => _changeYear(year, 1) : null,
      );
      switch (yearValue) {
        case AsyncData(value: final stats) when stats.isEmpty:
          content = _Empty(
            title: l10n.statsYearEmptyTitle('${stats.year}'),
            text: l10n.statsYearEmptyText,
          );
        case AsyncData(value: final stats):
          content = _YearStats(
            stats: stats,
            today: today,
            onCategoryTap: (category, index) =>
                _openYearCategory(stats, category, index),
          );
        case AsyncError():
          content = _LoadFailed(text: l10n.statsYearLoadFailed);
        default:
          content = const SizedBox.shrink();
      }
    } else {
      period = _MonthPeriod(month: month, onTap: () => _openPicker(month));
      switch (value) {
        case AsyncData(value: final stats) when stats.isEmpty:
          content = _Empty(
            title: l10n.statsEmptyTitle(
              l10n.monthPrepositional(_monthKeys[stats.month.month - 1]),
            ),
            text: l10n.statsEmptyText,
          );
        case AsyncData(value: final stats):
          content = _MonthStats(
            stats: stats,
            onCategoryTap: (category, index) =>
                _openCategory(stats, category, index),
          );
        case AsyncError():
          content = _LoadFailed(text: l10n.statsLoadFailed);
        default:
          content = const SizedBox.shrink();
      }
    }

    return Scaffold(
      backgroundColor: colors.bgApp,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _TopBar(title: l10n.statsTitle, period: period),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(12, 0, 12, 20 + bottom),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Transform.translate(
                      offset: const Offset(0, -2),
                      child: AppSegmented<StatsMode>(
                        options: [
                          SegmentOption(StatsMode.month, l10n.statsModeMonth),
                          SegmentOption(StatsMode.year, l10n.statsModeYear),
                        ],
                        selected: _mode,
                        onChanged: _onMode,
                      ),
                    ),
                    const SizedBox(height: 8),
                    content,
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.title, required this.period});

  final String title;
  final Widget period;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 60),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 12, 6),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          runAlignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 4,
          children: [
            Semantics(
              header: true,
              child: FittingText(
                title,
                style: AppText.titleL.copyWith(color: colors.textPrimary),
              ),
            ),
            period,
          ],
        ),
      ),
    );
  }
}

class _MonthPeriod extends StatelessWidget {
  const _MonthPeriod({required this.month, required this.onTap});

  final YearMonth month;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final period = monthTitle(month);
    return Semantics(
      button: true,
      label: l10n.a11yStatsChoosePeriod(period),
      excludeSemantics: true,
      onTap: onTap,
      child: AppChip(emoji: seasonEmoji(month), label: period, onTap: onTap),
    );
  }
}

class _YearPeriod extends StatelessWidget {
  const _YearPeriod({required this.year, this.onPrevious, this.onNext});

  final int year;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  static const double arrow = 32;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Stack(
      alignment: Alignment.center,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: arrow),
          child: Semantics(
            label: l10n.a11yStatsChooseYear('$year'),
            excludeSemantics: true,
            child: AppChip(emoji: '📅', label: '$year'),
          ),
        ),
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: kMinTapTarget,
          child: _YearArrow(
            icon: AppIcons.chevronLeft,
            label: l10n.a11yPrevYear,
            alignment: Alignment.centerLeft,
            onTap: onPrevious,
          ),
        ),
        Positioned(
          right: 0,
          top: 0,
          bottom: 0,
          width: kMinTapTarget,
          child: _YearArrow(
            icon: AppIcons.chevronRight,
            label: l10n.a11yNextYear,
            alignment: Alignment.centerRight,
            onTap: onNext,
          ),
        ),
      ],
    );
  }
}

class _YearArrow extends StatelessWidget {
  const _YearArrow({
    required this.icon,
    required this.label,
    required this.alignment,
    this.onTap,
  });

  final AppIcons icon;
  final String label;
  final Alignment alignment;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final enabled = onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Align(
          alignment: alignment,
          child: Material(
            type: MaterialType.transparency,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: SizedBox.square(
                dimension: _YearPeriod.arrow,
                child: Center(
                  child: AppIcon(
                    icon,
                    size: 18,
                    color: enabled ? colors.textPrimary : colors.textDisabled,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MonthStats extends StatelessWidget {
  const _MonthStats({required this.stats, required this.onCategoryTap});

  final StatsMonth stats;
  final void Function(StatsCategory category, int index) onCategoryTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DonutCard(stats: stats),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            children: [
              Semantics(
                header: true,
                child: FittingText(
                  l10n.statsByCategory,
                  style: AppText.titleS.copyWith(color: colors.textPrimary),
                ),
              ),
              FittingText(
                l10n.statsBySum,
                style: AppText.labelS.copyWith(color: colors.textTertiary),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Material(
          color: colors.bgSurface,
          borderRadius: BorderRadius.circular(RadiusTokens.lg),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, category) in stats.categories.indexed)
                  _CategoryRow(
                    category: category,
                    onTap: () => onCategoryTap(category, i),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.category, required this.onTap});

  final StatsCategory category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final expenses = l10n.statsExpenses(category.count);
    return Semantics(
      button: true,
      label: l10n.a11yStatsRow(
        category.name,
        category.percent,
        expenses,
        l10n.a11yRubles(category.total.roundedRubles),
      ),
      excludeSemantics: true,
      onTap: onTap,
      child: StatRow(
        emoji: category.emoji,
        color: category.color,
        name: category.name,
        share: l10n.statsShare(category.percent, expenses),
        amount: category.total.formatTotal(),
        fraction: category.fraction,
        onTap: onTap,
      ),
    );
  }
}

class _DonutCard extends StatelessWidget {
  const _DonutCard({required this.stats});

  final StatsMonth stats;

  static const double _padding = 18;

  static const double _gap = 20;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final count = stats.categories.length;
    final donut = Semantics(
      label: l10n.a11yStatsDonut(count),
      excludeSemantics: true,
      child: DonutChart(
        segments: [
          for (final c in stats.categories)
            DonutSegment(
              weight: c.total.kopecks,
              color: colors.category(c.color)?.solid ?? colors.textTertiary,
            ),
        ],
        center: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$count',
              style: AppText.titleL.copyWith(color: colors.textPrimary),
            ),
            Text(
              l10n.statsCategoriesCount(count),
              style: AppText.caption.copyWith(color: colors.textTertiary),
            ),
          ],
        ),
      ),
    );
    final total = stats.total.formatTotal();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.bgSurface,
        borderRadius: BorderRadius.circular(RadiusTokens.xl),
        boxShadow: ShadowTokens.card,
      ),
      child: Padding(
        padding: const EdgeInsets.all(_padding),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final side = constraints.maxWidth - donutSize - _gap;
            final summary = _Summary(stats: stats);
            final fits =
                FittingText.widestWord(context, total, AppText.displayM) <=
                side;
            if (fits) {
              return Row(
                children: [
                  donut,
                  const SizedBox(width: _gap),
                  Expanded(child: summary),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(child: donut),
                const SizedBox(height: _gap),
                summary,
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.stats});

  final StatsMonth stats;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final comparison = stats.comparison;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        FittingText(
          l10n.statsTotal(monthName(stats.month)),
          style: AppText.caption.copyWith(color: colors.textTertiary),
        ),
        const SizedBox(height: 6),
        FittingText(
          stats.total.formatTotal(),
          style: AppText.displayM.copyWith(color: colors.textPrimary),
        ),
        if (comparison != null) ...[
          const SizedBox(height: 6),
          _Trend(comparison: comparison, previous: stats.previous),
        ],
        const SizedBox(height: 6),
        FittingText(
          l10n.statsAverage(stats.average?.formatTotal() ?? '—'),
          style: AppText.caption.copyWith(color: colors.textSecondary),
        ),
      ],
    );
  }
}

class _Trend extends StatelessWidget {
  const _Trend({required this.comparison, required this.previous});

  final MonthComparison comparison;
  final YearMonth previous;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final percent = comparison.percent;
    final color = percent < 0
        ? colors.statusSuccess
        : percent > 0
        ? colors.statusDanger
        : colors.textSecondary;
    final icon = AppIcon(AppIcons.trendingDown, size: 14, color: color);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.bgSurface2,
        borderRadius: BorderRadius.circular(RadiusTokens.full),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 10, 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (percent != 0) ...[
              percent < 0 ? icon : Transform.flip(flipY: true, child: icon),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: FittingText(
                l10n.statsComparison(
                  statsPercent(percent),
                  l10n.monthDative(_monthKeys[previous.month - 1]),
                ),
                style: AppText.labelS.copyWith(color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.title, required this.text});

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final mood = context.mood;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 88, 20, 0),
      child: Column(
        children: [
          ExcludeSemantics(
            child: Container(
              width: 88,
              height: 88,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: mood.soft,
                shape: BoxShape.circle,
              ),
              child: AppIcon(
                AppIcons.pieChart,
                size: 36,
                color: mood.accentStrong,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Semantics(
            header: true,
            child: FittingText(
              title,
              textAlign: TextAlign.center,
              style: AppText.titleM.copyWith(color: colors.textPrimary),
            ),
          ),
          const SizedBox(height: 10),
          FittingText(
            text,
            textAlign: TextAlign.center,
            style: AppText.bodyM.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _LoadFailed extends StatelessWidget {
  const _LoadFailed({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 88, 20, 0),
      child: FittingText(
        text,
        textAlign: TextAlign.center,
        style: AppText.bodyM.copyWith(color: colors.textSecondary),
      ),
    );
  }
}

class _YearStats extends StatelessWidget {
  const _YearStats({
    required this.stats,
    required this.today,
    required this.onCategoryTap,
  });

  final StatsYear stats;
  final LocalDate today;
  final void Function(StatsCategory category, int index) onCategoryTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _YearCard(stats: stats, today: today),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Semantics(
            header: true,
            child: FittingText(
              l10n.statsYearByCategory,
              style: AppText.titleS.copyWith(color: colors.textPrimary),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Material(
          color: colors.bgSurface,
          borderRadius: BorderRadius.circular(RadiusTokens.lg),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, category) in stats.categories.indexed)
                  _CategoryRow(
                    category: category,
                    onTap: () => onCategoryTap(category, i),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _YearCard extends StatelessWidget {
  const _YearCard({required this.stats, required this.today});

  final StatsYear stats;
  final LocalDate today;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final priciest = stats.priciest;
    final current = YearMonth.of(today);
    final ongoing = monthName(current);
    final caption = [
      if (priciest != null)
        l10n.statsYearPriciest(
          monthName(YearMonth(stats.year, priciest)),
          stats.months[priciest - 1].formatTotal(),
        ),
      if (stats.year == today.year)
        l10n.statsYearOngoing(
          '${ongoing[0].toUpperCase()}${ongoing.substring(1)}',
        ),
    ].join(' ');
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.bgSurface,
        borderRadius: BorderRadius.circular(RadiusTokens.xl),
        boxShadow: ShadowTokens.card,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _YearTotals(stats: stats),
            const SizedBox(height: 12),
            YearChart(year: stats.year, today: today, totals: stats.months),
            if (caption.isNotEmpty) ...[
              const SizedBox(height: 12),
              FittingText(
                caption,
                style: AppText.caption.copyWith(color: colors.textTertiary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _YearTotals extends StatelessWidget {
  const _YearTotals({required this.stats});

  final StatsYear stats;

  static const double _spacing = 12;

  static double _lineWidth(BuildContext context, String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: DefaultTextStyle.of(context).style.merge(style),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final totalLabel = l10n.statsYearTotal('${stats.year}');
    final total = stats.total.formatTotal();
    final averageLabel = l10n.statsYearAverageLabel;
    final average = l10n.statsYearAverage(stats.average?.formatTotal() ?? '—');
    final labelStyle = AppText.caption.copyWith(color: colors.textTertiary);
    final totalStyle = AppText.displayM.copyWith(color: colors.textPrimary);
    final averageStyle = AppText.labelM.copyWith(color: colors.textSecondary);
    return LayoutBuilder(
      builder: (context, constraints) {
        final left = math.max(
          _lineWidth(context, totalLabel, labelStyle),
          _lineWidth(context, total, totalStyle),
        );
        final right = math.max(
          _lineWidth(context, averageLabel, labelStyle),
          _lineWidth(context, average, averageStyle),
        );
        final row = left + _spacing + right <= constraints.maxWidth;
        final totals = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FittingText(totalLabel, style: labelStyle),
            const SizedBox(height: 2),
            FittingText(total, style: totalStyle),
          ],
        );
        final averages = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: row
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            FittingText(averageLabel, style: labelStyle),
            const SizedBox(height: 2),
            FittingText(average, style: averageStyle),
          ],
        );
        if (row) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [totals, averages],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [totals, const SizedBox(height: 8), averages],
        );
      },
    );
  }
}
