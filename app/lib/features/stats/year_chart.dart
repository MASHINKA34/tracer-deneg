import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared/shared.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/theme/app_text.dart';
import '../../ui/theme/app_theme.dart';
import '../month/month_picker_sheet.dart' show monthTitle, priciestMonth;
import 'stats_year.dart';

const double yearBarMaxHeight = 110;

const double yearBarWidth = 16;

const double yearFutureBarHeight = 4;

const double yearBarMinGap = 4;

const double _gap = 6;

List<double> yearBarHeights(List<Money> totals) {
  final max = totals.fold<int>(0, (m, t) => math.max(m, t.kopecks));
  return [
    for (final total in totals)
      max <= 0 || total.kopecks <= 0
          ? 0
          : (yearBarMaxHeight * total.kopecks / max).roundToDouble(),
  ];
}

class YearChart extends StatelessWidget {
  const YearChart({
    super.key,
    required this.year,
    required this.today,
    required this.totals,
  });

  final int year;
  final LocalDate today;
  final List<Money> totals;

  @override
  Widget build(BuildContext context) {
    final heights = yearBarHeights(totals);
    final priciest = priciestMonth(totals);
    final row = Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var m = 1; m <= 12; m++) ...[
          if (m > 1) const SizedBox(width: yearBarMinGap),
          YearChartColumn(
            month: YearMonth(year, m),
            kind: statsYearMonthKind(YearMonth(year, m), today),
            total: totals[m - 1],
            height: heights[m - 1],
            maxLabel: m == priciest ? totals[m - 1].formatCell() : null,
          ),
        ],
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) => FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.bottomLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: constraints.maxWidth),
          child: row,
        ),
      ),
    );
  }
}

class YearChartColumn extends StatelessWidget {
  const YearChartColumn({
    super.key,
    required this.month,
    required this.kind,
    required this.total,
    required this.height,
    this.maxLabel,
  });

  final YearMonth month;
  final StatsYearMonthKind kind;
  final Money total;
  final double height;
  final String? maxLabel;

  Color barColor(BuildContext context) => switch (kind) {
    StatsYearMonthKind.past => context.mood.heat3,
    StatsYearMonthKind.current => context.mood.accent,
    StatsYearMonthKind.future => context.colors.bgSurface3,
  };

  Color letterColor(BuildContext context) => switch (kind) {
    StatsYearMonthKind.past => context.colors.textSecondary,
    StatsYearMonthKind.current => context.mood.accentStrong,
    StatsYearMonthKind.future => context.colors.textDisabled,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final future = kind == StatsYearMonthKind.future;
    final title = monthTitle(month);
    final label = maxLabel;
    return Semantics(
      label: future
          ? l10n.a11yStatsYearBarFuture(title)
          : l10n.a11yStatsYearBar(title, l10n.a11yRubles(total.roundedRubles)),
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (label != null) ...[
            Text(
              label,
              maxLines: 1,
              softWrap: false,
              style: AppText.micro.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: _gap),
          ],
          SizedBox(
            width: yearBarWidth,
            height: future ? yearFutureBarHeight : height,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: barColor(context),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(6),
                  bottom: Radius.circular(2),
                ),
              ),
            ),
          ),
          const SizedBox(height: _gap),
          Text(
            title.characters.first,
            maxLines: 1,
            softWrap: false,
            style: AppText.labelS.copyWith(color: letterColor(context)),
          ),
        ],
      ),
    );
  }
}
