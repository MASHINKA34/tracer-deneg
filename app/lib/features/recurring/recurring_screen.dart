import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import '../../core/router.dart';
import '../../data/db/redact_db_error.dart';
import '../../data/providers.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/components/button.dart';
import '../../ui/components/expense_row.dart';
import '../../ui/components/fitting_text.dart';
import '../../ui/components/tap_target.dart';
import '../../ui/icons/app_icon.dart';
import '../../ui/theme/app_text.dart';
import '../../ui/theme/app_theme.dart';
import '../../ui/tokens/tokens.g.dart';
import '../month/day_sheet.dart' show spokenAmount;
import 'recurring_controller.dart';
import 'recurring_overview.dart';

final _log = Logger('recurring');

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

String recurringChargeDate(LocalDate date) => DateFormat(
  'd MMMM',
  'ru',
).format(DateTime(date.year, date.month, date.day));

class RecurringScreen extends ConsumerStatefulWidget {
  const RecurringScreen({super.key});

  @override
  ConsumerState<RecurringScreen> createState() => _RecurringScreenState();
}

class _RecurringScreenState extends ConsumerState<RecurringScreen> {
  Stopwatch _sw = Stopwatch()..start();
  bool _loading = true;
  ({String? budgetId, YearMonth month, int rules, int upcoming, int charged})?
  _shown;
  String? _failed;
  final Set<String> _reportedUnknown = {};

  @override
  void initState() {
    super.initState();
    _log.fine('recurring screen opened');
    ref.listenManual(recurringOverviewProvider, _onData, fireImmediately: true);
  }

  void _onData(
    AsyncValue<RecurringOverview>? previous,
    AsyncValue<RecurringOverview> next,
  ) {
    switch (next) {
      case AsyncData(value: final overview):
        _logBuilt(overview);
      case AsyncError(:final error, :final stackTrace):
        _logFailed(error, stackTrace);
      default:
        if (!_loading) {
          _loading = true;
          _sw = Stopwatch()..start();
        }
    }
  }

  void _logBuilt(RecurringOverview overview) {
    final shown = (
      budgetId: overview.budgetId,
      month: overview.month,
      rules: overview.ruleCount,
      upcoming: overview.upcoming.length,
      charged: overview.charged.length,
    );
    _failed = null;
    final previous = _shown;
    if (previous == shown) return;
    _shown = shown;
    if (_loading || previous == null || previous.budgetId != shown.budgetId) {
      _log.fine(
        'recurring screen built budgetId=${overview.budgetId ?? '-'} '
        'month=${overview.month} rules=${overview.ruleCount} '
        'upcoming=${overview.upcoming.length} '
        'charged=${overview.charged.length} '
        'monthlyKopecks=${overview.monthly.kopecks}'
        '${overview.budgetId == null ? ': no budget selected, empty state' : ''}'
        '${overview.budgetId != null && overview.isEmpty ? ': no rules, empty state' : ''}'
        ' in ${_sw.elapsedMilliseconds}ms',
      );
    } else {
      _log.fine(
        'recurring screen updated budgetId=${overview.budgetId} '
        'month=${previous.month} → ${shown.month} '
        'rules=${previous.rules} → ${shown.rules} '
        'upcoming=${previous.upcoming} → ${shown.upcoming} '
        'charged=${previous.charged} → ${shown.charged}',
      );
    }
    _loading = false;
    for (final id in overview.unknownCategoryIds) {
      if (!_reportedUnknown.add(id)) continue;
      _log.warning(
        'recurring rule category=$id of budgetId=${overview.budgetId} '
        'not found among live categories, row shown as system «other»',
      );
    }
  }

  void _logFailed(Object error, StackTrace stackTrace) {
    var what = 'data failed';
    var cause = error;
    while (true) {
      if (cause is ProviderException) {
        cause = cause.exception;
      } else if (cause is RecurringDataError) {
        what = cause.what;
        cause = cause.cause;
      } else {
        break;
      }
    }
    final budget = ref.read(selectedBudgetIdProvider);
    final budgetId = budget.hasError ? 'unknown' : budget.value ?? '-';
    final failed = '$budgetId $what';
    if (failed == _failed) return;
    _failed = failed;
    _loading = false;
    _shown = null;
    final redacted = redactDbError(cause);
    _log.severe(
      'recurring screen failed budgetId=$budgetId: $what '
      'after ${_sw.elapsedMilliseconds}ms, showing error text: '
      '${describeError(redacted)}',
      redacted,
      stackTrace,
    );
  }

  void _add(String from) {
    _log.fine('recurring add tap from=$from → ${AppRoutes.newRecurring}');
    context.push(AppRoutes.newRecurring);
  }

  void _open(RecurringRule rule, String section, int index) {
    _log.fine(
      'recurring rule tap section=$section #$index id=${rule.id} '
      'day=${rule.dayOfMonth} → ${AppRoutes.recurringRule}',
    );
    context.push(AppRoutes.recurringRuleOf(rule.id));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final value = ref.watch(recurringOverviewProvider);
    final bottom = MediaQuery.paddingOf(context).bottom;

    final Widget content;
    var canAdd = false;
    switch (value) {
      case AsyncData(value: final overview) when overview.budgetId == null:
        content = _Empty(onAdd: null, bottom: bottom);
      case AsyncData(value: final overview) when overview.isEmpty:
        content = _Empty(onAdd: () => _add('empty'), bottom: bottom);
      case AsyncData(value: final overview):
        canAdd = true;
        content = _Overview(overview: overview, bottom: bottom, onOpen: _open);
      case AsyncError():
        content = _LoadFailed(text: l10n.recurringLoadFailed);
      default:
        content = const SizedBox.shrink();
    }

    return Scaffold(
      backgroundColor: colors.bgApp,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _TopBar(
              title: l10n.recurringTitle,
              addLabel: l10n.recurringAdd,
              onAdd: canAdd ? () => _add('header') : null,
            ),
            Expanded(child: content),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.title, required this.addLabel, this.onAdd});

  final String title;
  final String addLabel;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final onAdd = this.onAdd;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 60),
      child: Padding(
        padding: EdgeInsets.only(left: 16, right: onAdd == null ? 12 : 8),
        child: Row(
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: FittingText(
                  title,
                  style: AppText.titleL.copyWith(color: colors.textPrimary),
                ),
              ),
            ),
            if (onAdd != null) ...[
              const SizedBox(width: 8),
              Semantics(
                button: true,
                label: addLabel,
                excludeSemantics: true,
                onTap: onAdd,
                child: TapTarget(
                  child: Material(
                    color: colors.bgSurface,
                    shape: CircleBorder(
                      side: BorderSide(color: colors.borderDefault),
                    ),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: onAdd,
                      child: SizedBox.square(
                        dimension: 40,
                        child: Center(
                          child: AppIcon(
                            AppIcons.plus,
                            size: 22,
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Overview extends StatelessWidget {
  const _Overview({
    required this.overview,
    required this.bottom,
    required this.onOpen,
  });

  final RecurringOverview overview;
  final double bottom;
  final void Function(RecurringRule rule, String section, int index) onOpen;

  static const double _gap = 14;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final month = l10n.monthPrepositional(_monthKeys[overview.month.month - 1]);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(12, 4, 12, 20 + bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SummaryCard(overview: overview),
          if (overview.upcoming.isNotEmpty) ...[
            const SizedBox(height: _gap),
            _SectionHead(
              title: l10n.recurringUpcoming,
              total: overview.upcomingTotal,
            ),
            const SizedBox(height: _gap),
            _RowsCard(
              rows: [
                for (final (i, item) in overview.upcoming.indexed)
                  _UpcomingRow(
                    item: item,
                    onTap: () => onOpen(item.rule, 'upcoming', i),
                  ),
              ],
            ),
          ],
          if (overview.charged.isNotEmpty) ...[
            const SizedBox(height: _gap),
            _SectionHead(
              title: l10n.recurringCharged(month),
              total: overview.chargedTotal,
            ),
            const SizedBox(height: _gap),
            _RowsCard(
              rows: [
                for (final (i, item) in overview.charged.indexed)
                  _ChargedRow(
                    item: item,
                    color: colors.statusSuccess,
                    onTap: () => onOpen(item.rule, 'charged', i),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.overview});

  final RecurringOverview overview;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final mood = context.mood;
    final summary = l10n.recurringSummary(overview.ruleCount);
    return Semantics(
      label: l10n.a11yRecurringMonthly(
        spokenAmount(l10n, overview.monthly),
        summary,
      ),
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: mood.soft,
          borderRadius: BorderRadius.circular(RadiusTokens.xl),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 18, 18),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FittingText(
                      l10n.recurringMonthly,
                      style: AppText.labelS.copyWith(color: mood.onSoft),
                    ),
                    const SizedBox(height: 4),
                    FittingText(
                      overview.monthly.formatTotal(),
                      style: AppText.displayL.copyWith(color: mood.onSoft),
                    ),
                    const SizedBox(height: 4),
                    FittingText(
                      summary,
                      style: AppText.caption.copyWith(color: mood.onSoft),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.bgSurface,
                  shape: BoxShape.circle,
                ),
                child: AppIcon(
                  AppIcons.repeat,
                  size: 24,
                  color: mood.accentStrong,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHead extends StatelessWidget {
  const _SectionHead({required this.title, required this.total});

  final String title;
  final Money total;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    return Semantics(
      header: true,
      label: l10n.a11ySection(title, spokenAmount(l10n, total)),
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 12,
          children: [
            FittingText(
              title,
              style: AppText.titleS.copyWith(color: colors.textPrimary),
            ),
            FittingText(
              total.formatTotal(),
              style: AppText.labelS.copyWith(color: colors.textTertiary),
            ),
          ],
        ),
      ),
    );
  }
}

class _RowsCard extends StatelessWidget {
  const _RowsCard({required this.rows});

  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.bgSurface,
      borderRadius: BorderRadius.circular(RadiusTokens.lg),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: rows,
        ),
      ),
    );
  }
}

class _UpcomingRow extends StatelessWidget {
  const _UpcomingRow({required this.item, required this.onTap});

  final UpcomingRecurring item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final rule = item.rule;
    final category = item.category;
    final other = presetCategories.firstWhere((p) => p.isSystem);
    final every = l10n.recurringEvery(rule.dayOfMonth);
    final inDays = l10n.recurringInDays(item.days);
    return Semantics(
      button: true,
      label: l10n.a11yRecurringUpcoming(
        rule.title,
        every,
        inDays,
        spokenAmount(l10n, rule.amount),
      ),
      excludeSemantics: true,
      onTap: onTap,
      child: ExpenseRow(
        emoji: category?.emoji ?? other.emoji,
        color: category == null ? other.color : category.color,
        title: rule.title,
        subtitle: l10n.recurringUpcomingSubtitle(every, inDays),
        amount: rule.amount.format(),
        onTap: onTap,
      ),
    );
  }
}

class _ChargedRow extends StatelessWidget {
  const _ChargedRow({
    required this.item,
    required this.color,
    required this.onTap,
  });

  final ChargedRecurring item;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final rule = item.rule;
    final category = item.category;
    final other = presetCategories.firstWhere((p) => p.isSystem);
    final date = recurringChargeDate(item.expense.spentOn);
    return Semantics(
      button: true,
      label: l10n.a11yRecurringCharged(
        rule.title,
        date,
        spokenAmount(l10n, item.expense.amount),
      ),
      excludeSemantics: true,
      onTap: onTap,
      child: ExpenseRow(
        emoji: category?.emoji ?? other.emoji,
        color: category == null ? other.color : category.color,
        title: rule.title,
        subtitle: l10n.recurringChargedOn(date),
        subtitleColor: color,
        amount: item.expense.amount.format(),
        onTap: onTap,
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.onAdd, required this.bottom});

  final VoidCallback? onAdd;
  final double bottom;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final mood = context.mood;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(32, 140, 32, 20 + bottom),
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
                AppIcons.repeat,
                size: 36,
                color: mood.accentStrong,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Semantics(
            header: true,
            child: FittingText(
              l10n.recurringEmptyTitle,
              textAlign: TextAlign.center,
              style: AppText.titleM.copyWith(color: colors.textPrimary),
            ),
          ),
          const SizedBox(height: 10),
          FittingText(
            l10n.recurringEmptyText,
            textAlign: TextAlign.center,
            style: AppText.bodyM.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: 6),
          AppButton(
            label: l10n.recurringAdd,
            size: AppButtonSize.m,
            onPressed: onAdd,
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
