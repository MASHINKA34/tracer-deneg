import 'dart:io';

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
import '../../data/queries/search_queries.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/components/button.dart';
import '../../ui/components/chip.dart';
import '../../ui/components/fitting_text.dart';
import '../../ui/components/snackbar.dart';
import '../../ui/components/tap_target.dart';
import '../../ui/icons/app_icon.dart';
import '../../ui/theme/app_text.dart';
import '../../ui/theme/app_theme.dart';
import '../../ui/tokens/tokens.g.dart';
import '../categories/categories_top_bar.dart';
import '../month/day_sheet.dart' show spokenAmount;
import '../search/search_period_sheet.dart'
    show searchFirstDate, searchRangePickerTheme;
import 'export_budget_sheet.dart';
import 'export_file.dart';
import 'export_rows.dart';

final _log = Logger('export');

final _nav = Logger('nav');

class ExportScreen extends ConsumerStatefulWidget {
  const ExportScreen({super.key});

  @override
  ConsumerState<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends ConsumerState<ExportScreen> {
  final Stopwatch _sinceSummary = Stopwatch()..start();
  ExportPeriodKind _kind = ExportPeriodKind.month;
  RangePeriod? _custom;
  String? _chosenBudgetId;
  bool _busy = false;
  String _closedBy = 'back';
  Object? _loggedBudgets;
  Object? _loggedSummary;
  Object? _loggedCategories;

  @override
  void initState() {
    super.initState();
    _log.fine('export screen opened period=${_kind.name}');
  }

  Object _unwrap(Object error) {
    var cause = error;
    while (cause is ProviderException) {
      cause = cause.exception;
    }
    return cause;
  }

  String _describe(String budgetId, ExportPeriod period) =>
      'budgetId=$budgetId period=${period.from}..${period.to} '
      'kind=${_kind.name}';

  void _logBudgets(AsyncValue<List<Budget>> next) {
    switch (next) {
      case AsyncData(value: final budgets):
        final chosen = _chosenBudgetId;
        _log.fine('export budgets loaded count=${budgets.length}');
        if (chosen != null && !budgets.any((b) => b.id == chosen)) {
          _log.warning(
            'export budget budgetId=$chosen is gone from ${budgets.length} '
            'budgets on the phone, back to the selected budget',
          );
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _chosenBudgetId = null);
          });
        }
      case AsyncError(:final error, :final stackTrace):
        final redacted = redactDbError(_unwrap(error));
        _log.severe(
          'export budgets list failed, budget sheet unavailable: '
          '${describeError(redacted)}',
          redacted,
          stackTrace,
        );
      default:
    }
  }

  void _logSummary(
    String budgetId,
    ExportPeriod period,
    AsyncValue<SearchResult> next,
  ) {
    switch (next) {
      case AsyncData(value: final result):
        _log.fine(
          'export summary ${_describe(budgetId, period)} '
          'rows=${result.count} total=${result.total.kopecks} kopecks '
          'in ${_sinceSummary.elapsedMilliseconds}ms',
        );
        if (result.count == 0) {
          _log.fine(
            'export share disabled: no expenses in '
            '${_describe(budgetId, period)}, empty-period note shown',
          );
        }
      case AsyncError(:final error, :final stackTrace):
        final redacted = redactDbError(_unwrap(error));
        _log.severe(
          'export summary failed ${_describe(budgetId, period)} after '
          '${_sinceSummary.elapsedMilliseconds}ms, share disabled and error '
          'note shown: ${describeError(redacted)}',
          redacted,
          stackTrace,
        );
      default:
    }
  }

  void _logCategories(String budgetId, AsyncValue<List<Category>> next) {
    if (next case AsyncError(:final error, :final stackTrace)) {
      final redacted = redactDbError(_unwrap(error));
      _log.severe(
        'export categories failed budgetId=$budgetId, share disabled and '
        'error note shown: ${describeError(redacted)}',
        redacted,
        stackTrace,
      );
    }
  }

  void _setKind(ExportPeriodKind kind) {
    if (kind == _kind) {
      _log.fine('export period stays ${kind.name}');
      return;
    }
    _log.fine('export period ${_kind.name} → ${kind.name}');
    _sinceSummary.reset();
    setState(() => _kind = kind);
  }

  Future<void> _pickRange() async {
    final today = ref.read(clockProvider).today();
    final current = _custom;
    final start = current == null
        ? today.yearMonth.firstDay
        : (current.from > today ? today : current.from);
    final end = current == null
        ? today
        : (current.to > today ? today : current.to);
    DateTime day(LocalDate d) => DateTime(d.year, d.month, d.day);
    final sw = Stopwatch()..start();
    _log.fine(
      'export date range picker opened initial=$start..$end '
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
    if (!mounted) return;
    if (picked == null) {
      _log.fine(
        'export date range picker cancelled after ${sw.elapsedMilliseconds}ms, '
        'period stays ${_kind.name}',
      );
      return;
    }
    final range = RangePeriod(
      LocalDate.fromDateTime(picked.start),
      LocalDate.fromDateTime(picked.end),
    );
    _log.fine(
      'export period ${_kind.name} → custom ${range.from}..${range.to} '
      'after ${sw.elapsedMilliseconds}ms',
    );
    _sinceSummary.reset();
    setState(() {
      _custom = range;
      _kind = ExportPeriodKind.custom;
    });
  }

  Future<void> _chooseBudget(List<Budget> budgets, String? current) async {
    final chosen = await showExportBudgetSheet(
      context,
      budgets: budgets,
      current: current,
    );
    if (!mounted || chosen == null) return;
    if (chosen == current) {
      _log.fine('export budget stays budgetId=$current');
      return;
    }
    _log.fine('export budget budgetId=$current → $chosen');
    _sinceSummary.reset();
    setState(() => _chosenBudgetId = chosen);
  }

  Future<void> _share({
    required Budget budget,
    required ExportPeriod period,
    required SearchResult result,
    required List<Category> categories,
  }) async {
    if (_busy) {
      _log.fine('export tap ignored: previous export is still running');
      return;
    }
    final l10n = AppLocalizations.of(context);
    final files = ref.read(exportFilesProvider);
    final sharer = ref.read(exportSharerProvider);
    final currentUser = ref.read(currentUserProvider);
    final members = ref.read(membersRepositoryProvider);
    final what = _describe(budget.id, period);
    final sw = Stopwatch()..start();
    _busy = true;
    _log.info('export started $what rows=${result.count}');
    try {
      final List<int> bytes;
      final int rows;
      try {
        final userId = await currentUser.userId();
        final profiles = {
          for (final p in await members.watchProfiles().first) p.userId: p,
        };
        final budgetName = exportBudgetName(l10n, budget);
        final csvRows = exportRows(
          expenses: result.expenses,
          categories: categories,
          budgetName: budgetName,
          authorOf: (id) => exportAuthorName(
            l10n,
            id,
            currentUserId: userId,
            profiles: profiles,
          ),
        );
        rows = csvRows.length;
        bytes = buildExpensesCsvBytes(csvRows);
        _log.fine(
          'export csv built rows=$rows profiles=${profiles.length} '
          'size=${bytes.length}B in ${sw.elapsedMilliseconds}ms',
        );
      } catch (e, st) {
        final redacted = redactDbError(_unwrap(e));
        _log.severe(
          'export csv build failed $what after ${sw.elapsedMilliseconds}ms, '
          'snackbar shown: ${describeError(redacted)}',
          redacted,
          st,
        );
        if (mounted) showAppSnackbar(context, text: l10n.exportWriteFailed);
        return;
      }
      final File file;
      try {
        file = await files.write(
          csvFileName(exportBudgetName(l10n, budget), period),
          bytes,
        );
      } catch (e) {
        _log.warning(
          'export aborted $what after ${sw.elapsedMilliseconds}ms: file not '
          'written (${e.runtimeType}), snackbar shown',
        );
        if (mounted) showAppSnackbar(context, text: l10n.exportWriteFailed);
        return;
      }
      _log.info(
        'export file ready $what rows=$rows size=${bytes.length}B '
        'in ${sw.elapsedMilliseconds}ms, opening share sheet',
      );
      final shareSw = Stopwatch()..start();
      try {
        final shared = await sharer.share(file);
        _log.info(
          'export share result=${shared.status.name} '
          'target=${shared.raw.isEmpty ? '-' : shared.raw} rows=$rows '
          'size=${bytes.length}B after ${shareSw.elapsedMilliseconds}ms',
        );
      } catch (e, st) {
        _log.severe(
          'export share failed path=${file.path} after '
          '${shareSw.elapsedMilliseconds}ms, snackbar shown: '
          '${describeError(e)}',
          e,
          st,
        );
        if (mounted) showAppSnackbar(context, text: l10n.exportShareFailed);
      }
    } finally {
      _busy = false;
    }
  }

  void _back() {
    _closedBy = 'back button';
    if (context.canPop()) {
      context.pop();
      return;
    }
    _nav.fine(
      'export closed by back button with nothing under it → '
      '${AppRoutes.month}',
    );
    context.go(AppRoutes.month);
  }

  void _handlePop(bool didPop, Object? result) {
    if (!didPop) return;
    _nav.fine('export closed by $_closedBy');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final today = ref.watch(clockProvider).today();
    final period = exportPeriodOf(_kind, today, custom: _custom);

    final budgetsValue = ref.watch(exportBudgetsProvider);
    if (!identical(budgetsValue, _loggedBudgets)) {
      _loggedBudgets = budgetsValue;
      _logBudgets(budgetsValue);
    }
    final budgets = budgetsValue.hasError ? null : budgetsValue.value;
    final selectedId = ref.watch(selectedBudgetIdProvider).value;
    final budgetId = _chosenBudgetId ?? selectedId;
    final budget = budgets?.where((b) => b.id == budgetId).firstOrNull;

    AsyncValue<SearchResult>? summary;
    AsyncValue<List<Category>>? categories;
    if (budget != null) {
      final watchedSummary = ref.watch(
        searchProvider(
          SearchFilters(budgetId: budget.id, from: period.from, to: period.to),
        ),
      );
      if (!identical(watchedSummary, _loggedSummary)) {
        _loggedSummary = watchedSummary;
        _logSummary(budget.id, period, watchedSummary);
      }
      final watchedCategories = ref.watch(categoriesProvider(budget.id));
      if (!identical(watchedCategories, _loggedCategories)) {
        _loggedCategories = watchedCategories;
        _logCategories(budget.id, watchedCategories);
      }
      summary = watchedSummary;
      categories = watchedCategories;
    }
    final result = summary is AsyncData<SearchResult> ? summary.value : null;
    final categoryList = categories is AsyncData<List<Category>>
        ? categories.value
        : null;
    final failed =
        budgetsValue.hasError ||
        (summary?.hasError ?? false) ||
        (categories?.hasError ?? false);
    final fileName = budget == null
        ? null
        : csvFileName(exportBudgetName(l10n, budget), period);
    final note = failed
        ? l10n.exportLoadFailed
        : result != null && result.count == 0
        ? l10n.exportEmpty
        : null;
    VoidCallback? onShare;
    if (!failed &&
        budget != null &&
        result != null &&
        result.count > 0 &&
        categoryList != null) {
      onShare = () => _share(
        budget: budget,
        period: period,
        result: result,
        categories: categoryList,
      );
    }

    return PopScope<Object?>(
      onPopInvokedWithResult: _handlePop,
      child: Scaffold(
        backgroundColor: colors.bgApp,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SafeArea(
              bottom: false,
              child: CategoriesTopBar(title: l10n.exportTitle, onBack: _back),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  16,
                  6,
                  16,
                  24 + MediaQuery.paddingOf(context).bottom,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ExportBudgetRow(
                      emoji: budget?.emoji,
                      name: budget == null
                          ? null
                          : exportBudgetName(l10n, budget),
                      onTap: budgets == null
                          ? null
                          : () => _chooseBudget(budgets, budget?.id),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      l10n.exportPeriod,
                      style: AppText.labelS.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        AppChip(
                          label: exportMonthChip(today),
                          selected: _kind == ExportPeriodKind.month,
                          onTap: () => _setKind(ExportPeriodKind.month),
                        ),
                        AppChip(
                          label: exportYearChip(l10n, today),
                          selected: _kind == ExportPeriodKind.year,
                          onTap: () => _setKind(ExportPeriodKind.year),
                        ),
                        AppChip(
                          label: exportCustomChip(
                            l10n,
                            _kind == ExportPeriodKind.custom ? _custom : null,
                          ),
                          selected: _kind == ExportPeriodKind.custom,
                          onTap: _pickRange,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ExportFileCard(
                      fileName: fileName ?? '',
                      count: result?.count,
                      total: result?.total,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      l10n.exportColumns,
                      style: AppText.caption.copyWith(
                        color: colors.textTertiary,
                      ),
                    ),
                    const SizedBox(height: 14),
                    AppButton(
                      label: l10n.exportShare,
                      icon: AppIcons.share,
                      expand: true,
                      onPressed: onShare,
                    ),
                    if (note != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        note,
                        textAlign: TextAlign.center,
                        style: AppText.caption.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
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

class ExportBudgetRow extends StatelessWidget {
  const ExportBudgetRow({
    super.key,
    required this.emoji,
    required this.name,
    required this.onTap,
  });

  final String? emoji;
  final String? name;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final value = name == null ? '' : '${emoji ?? ''} $name'.trim();
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: name == null ? l10n.exportBudget : '${l10n.exportBudget}, $name',
      excludeSemantics: true,
      onTap: onTap,
      child: TapTarget(
        minWidth: 0,
        child: Material(
          color: colors.bgSurface,
          borderRadius: BorderRadius.circular(RadiusTokens.lg),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 12,
                      runSpacing: 2,
                      children: [
                        FittingText(
                          l10n.exportBudget,
                          style: AppText.bodyM.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                        FittingText(
                          value,
                          style: AppText.labelM.copyWith(
                            color: colors.textPrimary,
                          ),
                        ),
                      ],
                    ),
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
      ),
    );
  }
}

class ExportFileCard extends StatelessWidget {
  const ExportFileCard({
    super.key,
    required this.fileName,
    required this.count,
    required this.total,
  });

  final String fileName;
  final int? count;
  final Money? total;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final mood = context.mood;
    final count = this.count;
    final total = this.total;
    final summary = count == null || total == null
        ? ''
        : l10n.exportSummary(count, total.formatTotal());
    return Semantics(
      container: true,
      label: count == null || total == null
          ? fileName
          : l10n.a11yExportFile(
              fileName,
              count,
              spokenAmount(l10n, Money.rubles(total.roundedRubles)),
            ),
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: mood.soft,
          borderRadius: BorderRadius.circular(RadiusTokens.lg),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.bgSurface,
                borderRadius: BorderRadius.circular(RadiusTokens.sm),
              ),
              child: AppIcon(
                AppIcons.download,
                size: 22,
                color: mood.accentStrong,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    fileName.replaceAll('_', '_​'),
                    style: AppText.labelM.copyWith(color: mood.onSoft),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    summary,
                    style: AppText.caption.copyWith(color: mood.onSoft),
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
