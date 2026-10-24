import 'dart:async';

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
import '../../data/queries/query_runner.dart' show describePeriod;
import '../../data/queries/search_queries.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/components/chip.dart';
import '../../ui/icons/app_icon.dart';
import '../../ui/theme/app_theme.dart';
import '../budgets/expense_authors.dart' show expenseAuthorsProvider;
import '../month/day_sheet.dart' show expenseCategory;
import 'search_categories_sheet.dart';
import 'search_field.dart';
import 'search_period.dart';
import 'search_period_sheet.dart';
import 'search_results.dart';

final _nav = Logger('nav');
final _log = Logger('search');

const Duration searchDebounce = Duration(milliseconds: 250);

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key, this.query = const {}});

  final Map<String, String> query;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode();
  final Set<String> _reportedCategories = {};
  Timer? _debounce;
  bool _ready = false;
  bool _backTapped = false;
  String _query = '';
  SearchPeriod _period = SearchPeriod.all;
  Set<String> _categoryIds = const {};
  String? _budgetId;
  SearchFilters? _filters;
  String _trigger = 'open';
  Stopwatch _sw = Stopwatch();
  bool _reported = false;
  ProviderSubscription<AsyncValue<SearchResult>>? _search;
  ProviderSubscription<AsyncValue<List<Category>>>? _categoriesSub;
  List<Category>? _categories;
  SearchResult? _result;
  bool _failed = false;

  LocalDate get _today => ref.read(clockProvider).today();

  @override
  void initState() {
    super.initState();
    final filter = SearchRouteFilter.fromQuery(widget.query);
    if (filter.isEmpty) {
      _nav.fine('search opened without filter');
    } else {
      _nav.fine('search opened with filter $filter');
    }
    final categoryId = filter.categoryId;
    if (categoryId != null) _categoryIds = {categoryId};
    final from = filter.from;
    final to = filter.to;
    if (from != null && to != null) {
      _period = SearchPeriod.ofRange(from, to, today: _today);
    } else if (from != null || to != null) {
      _log.warning(
        'search route period ${from ?? ''}..${to ?? ''} has only one end, '
        'searching for all time',
      );
    }
    if (!filter.isEmpty) {
      _log.fine(
        'search filters from route: period=$_period '
        'categories=${_categoryIds.length}',
      );
    }
    ref.listenManual(
      selectedBudgetIdProvider,
      _onBudget,
      fireImmediately: true,
    );
    _ready = true;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search?.close();
    _categoriesSub?.close();
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _update(VoidCallback change) {
    if (_ready && mounted) {
      setState(change);
    } else {
      change();
    }
  }

  void _onBudget(AsyncValue<String?>? previous, AsyncValue<String?> next) {
    switch (next) {
      case AsyncData(value: null):
        _closeData();
        _budgetId = null;
        _log.fine(
          'search without budget: no budget selected, nothing to search, '
          'empty state shown',
        );
        _update(() {
          _failed = false;
          _result = const SearchResult(
            expenses: [],
            count: 0,
            total: Money.zero,
          );
        });
      case AsyncData(value: final String budgetId) when budgetId != _budgetId:
        _closeData();
        _budgetId = budgetId;
        _categoriesSub = ref.listenManual<AsyncValue<List<Category>>>(
          categoriesProvider(budgetId),
          (previous, next) => _onCategories(budgetId, next),
          fireImmediately: true,
        );
        _run('open');
      case AsyncError(:final error, :final stackTrace):
        _logFailed('selected budget unavailable', error, stackTrace);
        _update(() => _failed = true);
      default:
    }
  }

  void _closeData() {
    _search?.close();
    _search = null;
    _categoriesSub?.close();
    _categoriesSub = null;
    _filters = null;
  }

  void _onCategories(String budgetId, AsyncValue<List<Category>> next) {
    switch (next) {
      case AsyncData(value: final categories):
        _update(() => _categories = categories);
        final live = {for (final c in categories) c.id};
        final missing = _categoryIds.where((id) => !live.contains(id));
        if (missing.isEmpty) return;
        for (final id in missing) {
          _log.warning(
            'search filter category=$id not found among '
            '${categories.length} live categories of budgetId=$budgetId, '
            'filter dropped',
          );
        }
        _update(
          () => _categoryIds = Set.unmodifiable(
            _categoryIds.where(live.contains),
          ),
        );
        _run('category missing');
      case AsyncError(:final error, :final stackTrace):
        _logFailed(
          'categories stream failed budgetId=$budgetId, rows shown as '
          '«Другое», categories filter unavailable',
          error,
          stackTrace,
        );
      default:
    }
  }

  String _describe(SearchFilters filters) =>
      'length=${filters.text.length} '
      'amount=${parseAmountQuery(filters.text) != null} '
      'period=${_period.kind.name} '
      'range=${describePeriod(filters.from, filters.to)} '
      'categories=${filters.categoryIds.length} budget=${filters.budgetId}';

  void _run(String trigger) {
    final budgetId = _budgetId;
    if (budgetId == null) {
      _log.fine('search trigger=$trigger skipped: no budget selected yet');
      return;
    }
    final range = _period.rangeOn(_today);
    final filters = SearchFilters(
      budgetId: budgetId,
      text: _query,
      from: range.from,
      to: range.to,
      categoryIds: _categoryIds,
    );
    if (filters == _filters) {
      _log.fine(
        'search trigger=$trigger skipped: filters unchanged '
        '${_describe(filters)}',
      );
      return;
    }
    _filters = filters;
    _trigger = trigger;
    _reported = false;
    _sw = Stopwatch()..start();
    _log.fine('search started trigger=$trigger ${_describe(filters)}');
    _search?.close();
    _search = ref.listenManual<AsyncValue<SearchResult>>(
      searchProvider(filters),
      (previous, next) => _onResult(filters, next),
      fireImmediately: true,
    );
  }

  void _onResult(SearchFilters filters, AsyncValue<SearchResult> next) {
    if (!identical(filters, _filters)) return;
    switch (next) {
      case AsyncData(value: final result):
        if (!_reported) {
          _reported = true;
          _log.fine(
            'search done trigger=$_trigger ${_describe(filters)} '
            'results=${result.count} in ${_sw.elapsedMilliseconds}ms',
          );
        } else {
          _log.fine(
            'search results updated ${_describe(filters)} '
            'results=${_result?.count} → ${result.count}: expenses changed',
          );
        }
        _update(() {
          _result = result;
          _failed = false;
        });
      case AsyncError(:final error, :final stackTrace):
        _logFailed(
          'search failed trigger=$_trigger ${_describe(filters)} after '
          '${_sw.elapsedMilliseconds}ms, error text shown',
          error,
          stackTrace,
        );
        _update(() => _failed = true);
      default:
    }
  }

  void _logFailed(String what, Object error, StackTrace stackTrace) {
    var cause = error;
    while (cause is ProviderException) {
      cause = cause.exception;
    }
    final redacted = redactDbError(cause);
    _log.severe('$what: ${describeError(redacted)}', redacted, stackTrace);
  }

  void _onTextChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(searchDebounce, () {
      _debounce = null;
      _applyQuery(text, 'typing');
    });
  }

  void _onSubmitted(String text) {
    _debounce?.cancel();
    _debounce = null;
    _applyQuery(text, 'submit');
  }

  void _clear() {
    _debounce?.cancel();
    _debounce = null;
    _log.fine('search query cleared by x button length=${_text.text.length}');
    _text.clear();
    _focus.requestFocus();
    _applyQuery('', 'clear');
  }

  void _applyQuery(String text, String trigger) {
    if (!mounted) return;
    _update(() => _query = text);
    _run(trigger);
  }

  void _setPeriod(SearchPeriod period) {
    if (period == _period) {
      _log.fine('search period stays $period');
      return;
    }
    _log.fine('search period $_period → $period');
    _update(() => _period = period);
    _run('period');
  }

  Future<void> _choosePeriod() async {
    final today = _today;
    _log.fine('search period chip tap current=$_period');
    final kind = await showSearchPeriodSheet(
      context,
      current: _period,
      today: today,
    );
    if (!mounted || kind == null) return;
    final SearchPeriod? period = switch (kind) {
      SearchPeriodKind.all => SearchPeriod.all,
      SearchPeriodKind.month => const SearchPeriod.month(),
      SearchPeriodKind.year => const SearchPeriod.year(),
      SearchPeriodKind.custom => await pickSearchRange(
        context,
        current: _period,
        today: today,
      ),
    };
    if (!mounted || period == null) return;
    _setPeriod(period);
  }

  Future<void> _chooseCategories() async {
    final categories = _categories;
    if (categories == null) {
      _log.warning(
        'search categories chip tap ignored: categories of '
        'budgetId=$_budgetId are not loaded',
      );
      return;
    }
    _log.fine('search categories chip tap selected=${_categoryIds.length}');
    await showSearchCategoriesSheet(
      context,
      categories: categories,
      selected: _categoryIds,
      onChanged: (ids) {
        if (!mounted) return;
        _log.fine('search categories ${_categoryIds.length} → ${ids.length}');
        _update(() => _categoryIds = ids);
        _run('categories');
      },
    );
  }

  void _reset() {
    final filtered = !_period.isAll || _categoryIds.isNotEmpty;
    if (filtered) {
      _log.fine(
        'search reset filters: period $_period → all, categories '
        '${_categoryIds.length} → 0, query kept length=${_query.length}',
      );
      _update(() {
        _period = SearchPeriod.all;
        _categoryIds = const {};
      });
    } else {
      _log.fine(
        'search reset: no filters set, query cleared length=${_query.length}',
      );
      _debounce?.cancel();
      _debounce = null;
      _text.clear();
      _update(() => _query = '');
    }
    _run('reset');
  }

  void _open(Expense expense) {
    _log.fine('search result tap id=${expense.id} → ${AppRoutes.expense}');
    context.push(AppRoutes.expenseOf(expense.id));
  }

  Category? _categoryOf(Expense expense, List<Category> categories) {
    final category = expenseCategory(expense, categories);
    if (category?.id != expense.categoryId &&
        _reportedCategories.add(expense.id)) {
      _log.warning(
        'search result id=${expense.id} category=${expense.categoryId} not '
        'found among ${categories.length} categories of budgetId=$_budgetId, '
        'showing it as '
        '${category == null ? 'preset other' : 'system category ${category.id}'}',
      );
    }
    return category;
  }

  void _back() {
    _backTapped = true;
    context.pop();
  }

  void _handlePop(bool didPop, Object? result) {
    if (!didPop) return;
    _nav.fine('search closed by ${_backTapped ? 'back button' : 'back'}');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final today = ref.watch(clockProvider).today();
    final budgetId = _budgetId;
    final budgetValue = budgetId == null
        ? null
        : ref.watch(budgetProvider(budgetId));
    final budget = budgetValue == null || budgetValue.hasError
        ? null
        : budgetValue.value;
    final categories = _categories ?? const <Category>[];
    final authors = budgetId == null
        ? null
        : ref.watch(expenseAuthorsProvider(budgetId));
    final selectedCategories = [
      for (final c in categories)
        if (_categoryIds.contains(c.id)) c,
    ];
    final single = selectedCategories.length == 1 && _categoryIds.length == 1
        ? selectedCategories.single
        : null;
    final result = _result;

    return PopScope<Object?>(
      onPopInvokedWithResult: _handlePop,
      child: Scaffold(
        backgroundColor: colors.bgApp,
        body: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 4, top: 6),
                child: Row(
                  children: [
                    Semantics(
                      button: true,
                      label: l10n.a11yBack,
                      excludeSemantics: true,
                      onTap: _back,
                      child: InkResponse(
                        radius: 22,
                        onTap: _back,
                        child: SizedBox.square(
                          dimension: 48,
                          child: Center(
                            child: AppIcon(
                              AppIcons.arrowLeft,
                              size: 24,
                              color: colors.textPrimary,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 2),
                    Expanded(
                      child: SearchField(
                        controller: _text,
                        focusNode: _focus,
                        onChanged: _onTextChanged,
                        onSubmitted: _onSubmitted,
                        onClear: _clear,
                      ),
                    ),
                  ],
                ),
              ),
              SearchFilterChips(
                chips: [
                  AppChip(
                    label: searchPeriodChipLabel(l10n, _period, today),
                    selected: !_period.isAll,
                    dropdown: true,
                    onTap: _choosePeriod,
                  ),
                  AppChip(
                    emoji: single?.emoji,
                    label: _categoryIds.isEmpty
                        ? l10n.searchCategoriesAll
                        : single?.name ??
                              l10n.searchCategoriesCount(_categoryIds.length),
                    selected: _categoryIds.isNotEmpty,
                    dropdown: true,
                    onTap: _chooseCategories,
                  ),
                  if (budget != null)
                    AppChip(
                      emoji: budget.emoji,
                      label: budget.kind == BudgetKind.personal
                          ? l10n.searchPersonalBudget
                          : budget.name,
                    ),
                ],
              ),
              Expanded(
                child: _failed
                    ? const SearchFailed()
                    : result == null
                    ? const SizedBox.shrink()
                    : result.count == 0 && result.expenses.isEmpty
                    ? SearchEmpty(onReset: _reset)
                    : SearchResults(
                        result: result,
                        today: today,
                        categoryOf: (e) => _categoryOf(e, categories),
                        authorOf: authors == null
                            ? null
                            : (e) => authors.of(e.authorId),
                        onOpen: _open,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
