import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/components/fitting_text.dart';
import '../../ui/components/radio.dart';
import '../../ui/components/sheet.dart';
import '../../ui/theme/app_text.dart';
import '../../ui/theme/app_theme.dart';
import '../../ui/tokens/tokens.g.dart';
import 'search_period.dart';

final _log = Logger('search');

final LocalDate searchFirstDate = LocalDate(2000, 1, 1);

Future<SearchPeriodKind?> showSearchPeriodSheet(
  BuildContext context, {
  required SearchPeriod current,
  required LocalDate today,
}) async {
  final sw = Stopwatch()..start();
  final root = Navigator.of(context, rootNavigator: true);
  _log.fine('search period sheet opened current=$current');
  final chosen = await showAppSheet<SearchPeriodKind>(
    root.context,
    builder: (context) => [
      SearchPeriodSheet(
        current: current,
        today: today,
        onSelected: (kind) => Navigator.of(context).pop(kind),
      ),
    ],
  );
  if (chosen == null) {
    _log.fine(
      'search period sheet closed without choice after '
      '${sw.elapsedMilliseconds}ms: back gesture, tap outside or swipe down, '
      'period stays $current',
    );
  } else {
    _log.fine(
      'search period sheet choice=${chosen.name} after '
      '${sw.elapsedMilliseconds}ms',
    );
  }
  return chosen;
}

Future<SearchPeriod?> pickSearchRange(
  BuildContext context, {
  required SearchPeriod current,
  required LocalDate today,
}) async {
  final sw = Stopwatch()..start();
  final range = current.isAll
      ? (from: today.yearMonth.firstDay, to: today)
      : current.rangeOn(today);
  DateTime day(LocalDate d) => DateTime(d.year, d.month, d.day);
  final start = range.from! > today ? today : range.from!;
  final end = range.to! > today ? today : range.to!;
  _log.fine(
    'search date range picker opened initial=$start..$end '
    'first=$searchFirstDate last=$today',
  );
  final picked = await showDateRangePicker(
    context: context,
    firstDate: day(searchFirstDate),
    lastDate: day(today),
    currentDate: day(today),
    initialDateRange: DateTimeRange(start: day(start), end: day(end)),
    locale: const Locale('ru'),
    builder: (context, child) => Theme(
      data: searchRangePickerTheme(context),
      child: child ?? const SizedBox.shrink(),
    ),
  );
  if (picked == null) {
    _log.fine(
      'search date range picker cancelled after ${sw.elapsedMilliseconds}ms, '
      'period stays $current',
    );
    return null;
  }
  final period = SearchPeriod.ofRange(
    LocalDate.fromDateTime(picked.start),
    LocalDate.fromDateTime(picked.end),
    today: today,
  );
  _log.fine(
    'search date range picked ${LocalDate.fromDateTime(picked.start)}..'
    '${LocalDate.fromDateTime(picked.end)} → period=$period after '
    '${sw.elapsedMilliseconds}ms',
  );
  return period;
}

ThemeData searchRangePickerTheme(BuildContext context) {
  final theme = Theme.of(context);
  final colors = context.colors;
  final mood = context.mood;
  final button = ButtonStyle(
    foregroundColor: WidgetStatePropertyAll(mood.accentStrong),
    textStyle: WidgetStatePropertyAll(AppText.labelL),
  );
  return theme.copyWith(
    datePickerTheme: DatePickerThemeData(
      backgroundColor: colors.bgSurface,
      surfaceTintColor: Colors.transparent,
      headerBackgroundColor: colors.bgSurface,
      headerForegroundColor: colors.textPrimary,
      rangePickerBackgroundColor: colors.bgApp,
      rangePickerSurfaceTintColor: Colors.transparent,
      rangePickerHeaderBackgroundColor: colors.bgApp,
      rangePickerHeaderForegroundColor: colors.textPrimary,
      rangePickerHeaderHeadlineStyle: AppText.titleL.copyWith(
        color: colors.textPrimary,
      ),
      rangePickerHeaderHelpStyle: AppText.labelS.copyWith(
        color: colors.textSecondary,
      ),
      rangeSelectionBackgroundColor: mood.soft,
      weekdayStyle: AppText.labelS.copyWith(color: colors.textTertiary),
      dayStyle: AppText.labelM,
      subHeaderForegroundColor: colors.textSecondary,
      todayForegroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? mood.onAccent
            : mood.accentStrong,
      ),
      todayBorder: BorderSide(color: mood.accentStrong),
      dayForegroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? colors.textDisabled
            : states.contains(WidgetState.selected)
            ? mood.onAccent
            : colors.textPrimary,
      ),
      dayBackgroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? mood.accent : null,
      ),
      dividerColor: colors.borderDefault,
      cancelButtonStyle: button,
      confirmButtonStyle: button,
    ),
    textButtonTheme: TextButtonThemeData(style: button),
  );
}

class SearchPeriodSheet extends StatelessWidget {
  const SearchPeriodSheet({
    super.key,
    required this.current,
    required this.today,
    required this.onSelected,
  });

  final SearchPeriod current;
  final LocalDate today;
  final ValueChanged<SearchPeriodKind> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final from = current.from;
    final to = current.to;
    final options = [
      (SearchPeriodKind.all, l10n.searchPeriodAll, null),
      (
        SearchPeriodKind.month,
        l10n.searchPeriodMonth,
        searchPeriodChipLabel(l10n, const SearchPeriod.month(), today),
      ),
      (
        SearchPeriodKind.year,
        l10n.searchPeriodYear,
        searchPeriodChipLabel(l10n, const SearchPeriod.year(), today),
      ),
      (
        SearchPeriodKind.custom,
        l10n.searchPeriodCustom,
        from == null || to == null ? null : searchPeriodLabel(l10n, from, to),
      ),
    ];
    return Flexible(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              header: true,
              child: FittingText(
                l10n.searchPeriodTitle,
                style: AppText.titleM.copyWith(color: colors.textPrimary),
              ),
            ),
            const SizedBox(height: 16),
            Material(
              color: colors.bgSurface2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(RadiusTokens.lg),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (final (kind, label, value) in options)
                    _PeriodRow(
                      label: label,
                      value: value,
                      selected: current.kind == kind,
                      onTap: () => onSelected(kind),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PeriodRow extends StatelessWidget {
  const _PeriodRow({
    required this.label,
    required this.value,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String? value;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final value = this.value;
    return MergeSemantics(
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FittingText(
                        label,
                        style: AppText.bodyL.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                      if (value != null)
                        FittingText(
                          value,
                          style: AppText.caption.copyWith(
                            color: colors.textTertiary,
                          ),
                        ),
                    ],
                  ),
                ),
                AppRadio(selected: selected, onTap: onTap),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
