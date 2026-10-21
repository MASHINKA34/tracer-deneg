import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:intl/intl.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import '../../core/clock.dart';
import '../../data/db/redact_db_error.dart';
import '../../data/providers.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/components/button.dart';
import '../../ui/components/fitting_text.dart';
import '../../ui/components/month_tab.dart';
import '../../ui/components/sheet.dart';
import '../../ui/icons/app_icon.dart';
import '../../ui/theme/app_text.dart';
import '../../ui/theme/app_theme.dart';

final _log = Logger('month');

const double monthBarArea = 72;

const double monthBarMaxHeight = 64;

const double _tabWidth = 26;

const double _headLift = 8;

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

List<double> monthBarHeights(List<Money> totals) {
  final max = totals.fold<int>(0, (m, t) => math.max(m, t.kopecks));
  return [
    for (final total in totals)
      max <= 0 || total.kopecks <= 0
          ? 0
          : (monthBarMaxHeight * total.kopecks / max).roundToDouble(),
  ];
}

int? priciestMonth(List<Money> totals) {
  int? best;
  for (var i = 0; i < totals.length; i++) {
    if (totals[i].kopecks <= 0) continue;
    if (best == null || totals[i] > totals[best]) best = i;
  }
  return best == null ? null : best + 1;
}

Money sumOfDays(Map<int, Money> days, LocalDate from, LocalDate to) =>
    Money.sum([
      for (final MapEntry(key: day, value: total) in days.entries)
        if (day >= from.day && day <= to.day) total,
    ]);

final class MonthPickerSummary {
  const MonthPickerSummary({
    required this.month,
    required this.total,
    required this.average,
    required this.period,
    required this.comparison,
  });

  factory MonthPickerSummary.of({
    required YearMonth month,
    required LocalDate today,
    required Money total,
    required Map<int, Money>? days,
    required Map<int, Money>? previousDays,
  }) {
    final period = comparisonPeriod(month, today);
    return MonthPickerSummary(
      month: month,
      total: total,
      average: averagePerDay(monthTotal: total, month: month, today: today),
      period: period,
      comparison: days == null || previousDays == null
          ? null
          : compareMonths(
              current: sumOfDays(days, period.currentFrom, period.currentTo),
              previous: sumOfDays(
                previousDays,
                period.previousFrom,
                period.previousTo,
              ),
            ),
    );
  }

  final YearMonth month;
  final Money total;
  final Money? average;
  final ComparisonPeriod period;
  final MonthComparison? comparison;
}

String monthName(YearMonth month) =>
    DateFormat.LLLL('ru').format(DateTime(month.year, month.month));

String _capitalized(String text) =>
    text.isEmpty ? text : '${text[0].toUpperCase()}${text.substring(1)}';

String monthTitle(YearMonth month) =>
    '${_capitalized(monthName(month))} ${month.year}';

String seasonEmoji(YearMonth month) => switch (seasonOf(month.month)) {
  Season.winter => '❄️',
  Season.spring => '🌷',
  Season.summer => '☀️',
  Season.autumn => '🍂',
};

String _describePeriod(ComparisonPeriod p) =>
    '${p.currentFrom}..${p.currentTo} with ${p.previousFrom}..${p.previousTo}';

Future<YearMonth?> showMonthPickerSheet(
  BuildContext context, {
  required YearMonth shown,
}) async {
  final sw = Stopwatch()..start();
  final root = Navigator.of(context, rootNavigator: true);
  _log.fine('month picker opened shown=$shown');
  final chosen = await showAppSheet<YearMonth>(
    root.context,
    builder: (context) => [MonthPicker(initial: shown)],
  );
  if (chosen == null) {
    _log.fine(
      'month picker closed without choice after ${sw.elapsedMilliseconds}ms: '
      'back gesture, tap outside or swipe down',
    );
  } else {
    _log.fine(
      'month picker closed: open $chosen after ${sw.elapsedMilliseconds}ms',
    );
  }
  return chosen;
}

class MonthPicker extends ConsumerStatefulWidget {
  const MonthPicker({super.key, required this.initial});

  final YearMonth initial;

  @override
  ConsumerState<MonthPicker> createState() => _MonthPickerState();
}

class _MonthPickerState extends ConsumerState<MonthPicker> {
  late int _year;
  late YearMonth _selected;

  @override
  void initState() {
    super.initState();
    final today = ref.read(clockProvider).today();
    var initial = widget.initial;
    if (isFutureMonth(initial, today)) {
      _log.warning(
        'month picker initial=$initial is in the future today=$today, '
        'selecting current month instead',
      );
      initial = YearMonth.of(today);
    }
    _year = initial.year;
    _selected = initial;
    _log.fine(
      'month picker year=$_year selected=$_selected, compare '
      '${_describePeriod(comparisonPeriod(_selected, today))}',
    );
    ref.listenManual(
      selectedBudgetIdProvider,
      _logBudget,
      fireImmediately: true,
    );
  }

  void _logBudget(AsyncValue<String?>? previous, AsyncValue<String?> next) {
    switch (next) {
      case AsyncData(value: null):
        _log.fine('month picker without budget: no budget selected, no sums');
      case AsyncError(:final error, :final stackTrace):
        _logFailed('unknown', 'selected budget unavailable', error, stackTrace);
      default:
    }
  }

  void _changeYear(int delta) {
    final today = ref.read(clockProvider).today();
    final from = _year;
    final to = from + delta;
    if (to > today.year || to < 1) {
      _log.fine(
        'month picker year $from → $to ignored: '
        '${to > today.year ? 'future year' : 'no earlier years'} '
        'today=$today',
      );
      return;
    }
    var selected = YearMonth(to, _selected.month);
    final future = isFutureMonth(selected, today);
    if (future) selected = YearMonth.of(today);
    setState(() {
      _year = to;
      _selected = selected;
    });
    _log.fine(
      'month picker year $from → $to by=arrow selected=$selected'
      '${future ? ' (same month is in the future, current month instead)' : ''}'
      ', compare ${_describePeriod(comparisonPeriod(selected, today))}',
    );
  }

  void _select(YearMonth month) {
    final from = _selected;
    if (month == from) {
      _log.fine('month picker tab $month: already selected');
      return;
    }
    final today = ref.read(clockProvider).today();
    setState(() => _selected = month);
    _log.fine(
      'month picker selected $from → $month by=tab, compare '
      '${_describePeriod(comparisonPeriod(month, today))}',
    );
  }

  void _open() {
    _log.fine('month picker open button month=$_selected');
    Navigator.of(context).pop(_selected);
  }

  void _logFailed(
    String budgetId,
    String what,
    Object error,
    StackTrace stackTrace,
  ) {
    var cause = error;
    while (cause is ProviderException) {
      cause = cause.exception;
    }
    final redacted = redactDbError(cause);
    _log.severe(
      'month picker data failed budgetId=$budgetId year=$_year '
      'selected=$_selected: $what, showing picker without sums: '
      '${describeError(redacted)}',
      redacted,
      stackTrace,
    );
  }

  void _listenData(String budgetId) {
    final year = _year;
    final month = _selected;
    ref.listen(yearMonthTotalsProvider((budgetId: budgetId, year: year)), (
      previous,
      next,
    ) {
      switch (next) {
        case AsyncData(value: final totals):
          _log.fine(
            'month picker year data budgetId=$budgetId year=$year '
            'monthsWithSpending=${totals.where((t) => !t.isZero).length} '
            'priciest=${priciestMonth(totals) ?? '-'}',
          );
        case AsyncError(:final error, :final stackTrace):
          _logFailed(budgetId, 'year totals stream failed', error, stackTrace);
        default:
      }
    });
    for (final (target, what) in [
      (month, 'month day totals stream failed'),
      (month.previous, 'previous month day totals stream failed'),
    ]) {
      ref.listen(dayTotalsProvider((budgetId: budgetId, month: target)), (
        previous,
        next,
      ) {
        if (next case AsyncError(:final error, :final stackTrace)) {
          _logFailed(budgetId, '$what month=$target', error, stackTrace);
        }
      });
    }
  }

  static T? _ok<T>(AsyncValue<T>? value) =>
      value == null || value.hasError ? null : value.value;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final today = ref.watch(clockProvider).today();
    final budgetId = _ok(ref.watch(selectedBudgetIdProvider));
    if (budgetId != null) _listenData(budgetId);

    final totals =
        (budgetId == null
            ? null
            : _ok(
                ref.watch(
                  yearMonthTotalsProvider((budgetId: budgetId, year: _year)),
                ),
              )) ??
        List<Money>.filled(12, Money.zero);
    final days = budgetId == null
        ? null
        : _ok(
            ref.watch(
              dayTotalsProvider((budgetId: budgetId, month: _selected)),
            ),
          );
    final previousDays = budgetId == null
        ? null
        : _ok(
            ref.watch(
              dayTotalsProvider((
                budgetId: budgetId,
                month: _selected.previous,
              )),
            ),
          );
    final summary = MonthPickerSummary.of(
      month: _selected,
      today: today,
      total: totals[_selected.month - 1],
      days: days,
      previousDays: previousDays,
    );
    final heights = monthBarHeights(totals);
    final priciest = priciestMonth(totals);

    return Flexible(
      child: Transform.translate(
        offset: const Offset(0, -_headLift),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Head(
                year: _year,
                onPrevious: _year > 1 ? () => _changeYear(-1) : null,
                onNext: _year < today.year ? () => _changeYear(1) : null,
              ),
              const SizedBox(height: 16 - _headLift),
              _Tabs(
                year: _year,
                today: today,
                selected: _selected,
                heights: heights,
                onSelect: _select,
              ),
              const SizedBox(height: 16),
              _Summary(summary: summary, today: today),
              const SizedBox(height: 16),
              FittingText(
                priciest == null
                    ? l10n.monthPickerLegend
                    : l10n.monthPickerLegendMax(
                        monthName(YearMonth(_year, priciest)),
                        totals[priciest - 1].formatTotal(),
                      ),
                style: AppText.caption.copyWith(color: colors.textTertiary),
              ),
              const SizedBox(height: 16),
              AppButton(
                label: l10n.monthPickerOpen(monthName(_selected)),
                expand: true,
                onPressed: _open,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Head extends StatelessWidget {
  const _Head({required this.year, this.onPrevious, this.onNext});

  final int year;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    return Row(
      children: [
        Expanded(
          child: FittingText(
            l10n.monthPickerTitle,
            style: AppText.titleM.copyWith(color: colors.textPrimary),
          ),
        ),
        _YearButton(
          icon: AppIcons.chevronLeft,
          label: l10n.a11yPrevYear,
          onTap: onPrevious,
          margin: const EdgeInsets.only(left: 8, right: 4),
        ),
        Text(
          '$year',
          style: AppText.labelL.copyWith(color: colors.textPrimary),
        ),
        _YearButton(
          icon: AppIcons.chevronRight,
          label: l10n.a11yNextYear,
          onTap: onNext,
          margin: const EdgeInsets.only(left: 4),
        ),
      ],
    );
  }
}

class _YearButton extends StatelessWidget {
  const _YearButton({
    required this.icon,
    required this.label,
    required this.margin,
    this.onTap,
  });

  final AppIcons icon;
  final String label;
  final EdgeInsets margin;
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
        child: Container(
          height: 48,
          padding: margin,
          alignment: Alignment.center,
          child: Material(
            color: colors.bgSurface2,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: SizedBox.square(
                dimension: 32,
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

class _Tabs extends StatelessWidget {
  const _Tabs({
    required this.year,
    required this.today,
    required this.selected,
    required this.heights,
    required this.onSelect,
  });

  final int year;
  final LocalDate today;
  final YearMonth selected;
  final List<double> heights;
  final ValueChanged<YearMonth> onSelect;

  @override
  Widget build(BuildContext context) {
    final row = Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var m = 1; m <= 12; m++) _tab(YearMonth(year, m), heights[m - 1]),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= _tabWidth * 12) return row;
        return FittedBox(
          fit: BoxFit.scaleDown,
          child: SizedBox(width: _tabWidth * 12, child: row),
        );
      },
    );
  }

  Widget _tab(YearMonth month, double height) {
    final future = isFutureMonth(month, today);
    final title = monthTitle(month);
    return MonthTab(
      letter: title.characters.first,
      state: future
          ? MonthTabState.future
          : month == selected
          ? MonthTabState.selected
          : MonthTabState.normal,
      fraction: height / monthBarArea,
      onTap: future ? null : () => onSelect(month),
      semanticLabel: title,
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.summary, required this.today});

  final MonthPickerSummary summary;
  final LocalDate today;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final mood = context.mood;
    final month = summary.month;
    final title = monthTitle(month);
    final comparison = summary.comparison;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: mood.soft,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FittingText(
                    month == YearMonth.of(today)
                        ? l10n.monthPickerNow(title)
                        : title,
                    style: AppText.labelS.copyWith(color: mood.onSoft),
                  ),
                  const SizedBox(height: 4),
                  FittingText(
                    summary.total.formatTotal(),
                    style: AppText.displayM.copyWith(color: mood.onSoft),
                  ),
                  if (comparison != null) ...[
                    const SizedBox(height: 4),
                    _Trend(comparison: comparison, previous: month.previous),
                  ],
                  const SizedBox(height: 4),
                  FittingText(
                    l10n.monthPickerAverage(
                      summary.average?.formatTotal() ?? '—',
                    ),
                    style: AppText.caption.copyWith(color: mood.onSoft),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              seasonEmoji(month),
              style: AppText.displayL.copyWith(color: colors.textPrimary),
            ),
          ],
        ),
      ),
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
    final mood = context.mood;
    final where = l10n.monthPrepositional(_monthKeys[previous.month - 1]);
    final amount = comparison.difference.abs;
    final same = amount.roundedRubles == 0;
    final (String text, Color color) = same
        ? (l10n.monthPickerSame(where), mood.onSoft)
        : comparison.isLess
        ? (
            l10n.monthPickerLess(amount.formatTotal(), where),
            colors.statusSuccess,
          )
        : (
            l10n.monthPickerMore(amount.formatTotal(), where),
            colors.statusDanger,
          );
    final icon = AppIcon(AppIcons.trendingDown, size: 16, color: color);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!same) ...[
          comparison.isLess ? icon : Transform.flip(flipY: true, child: icon),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: FittingText(
            text,
            style: AppText.caption.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}
