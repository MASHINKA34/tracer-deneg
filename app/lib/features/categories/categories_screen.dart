import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import '../../core/router.dart';
import '../../data/db/redact_db_error.dart';
import '../../data/providers.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/components/category_badge.dart';
import '../../ui/components/fitting_text.dart';
import '../../ui/icons/app_icon.dart';
import '../../ui/theme/app_text.dart';
import '../../ui/theme/app_theme.dart';
import '../../ui/tokens/tokens.g.dart';
import 'categories_top_bar.dart';

final _log = Logger('categories');

final _nav = Logger('nav');

class CategoriesScreen extends ConsumerStatefulWidget {
  const CategoriesScreen({super.key});

  @override
  ConsumerState<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends ConsumerState<CategoriesScreen> {
  final Stopwatch _sinceOpen = Stopwatch()..start();
  String _closedBy = 'back';
  int? _shown;
  Object? _loggedCategories;
  Object? _loggedCounts;

  @override
  void initState() {
    super.initState();
    _log.fine('categories list opened');
  }

  Object _unwrap(Object error) {
    var cause = error;
    while (cause is ProviderException) {
      cause = cause.exception;
    }
    return cause;
  }

  void _logCategories(String budgetId, AsyncValue<List<Category>> next) {
    switch (next) {
      case AsyncData(value: final categories):
        if (_shown == categories.length) return;
        _shown = categories.length;
        final custom = categories.where((c) => !c.isSystem).length;
        _log.fine(
          'categories shown budgetId=$budgetId count=${categories.length} '
          'editable=$custom system=${categories.length - custom} '
          'after ${_sinceOpen.elapsedMilliseconds}ms',
        );
      case AsyncError(:final error, :final stackTrace):
        final redacted = redactDbError(_unwrap(error));
        _log.severe(
          'categories list budgetId=$budgetId failed, error text shown '
          'instead of the list: ${describeError(redacted)}',
          redacted,
          stackTrace,
        );
      default:
    }
  }

  void _logCounts(String budgetId, AsyncValue<Map<String, int>> next) {
    if (next case AsyncError(:final error, :final stackTrace)) {
      final redacted = redactDbError(_unwrap(error));
      _log.severe(
        'categories list budgetId=$budgetId expense counts failed, rows '
        'shown without counts: ${describeError(redacted)}',
        redacted,
        stackTrace,
      );
    }
  }

  void _back() {
    _closedBy = 'back button';
    if (context.canPop()) {
      context.pop();
      return;
    }
    _nav.fine(
      'categories closed by back button with nothing under it → '
      '${AppRoutes.month}',
    );
    context.go(AppRoutes.month);
  }

  void _handlePop(bool didPop, Object? result) {
    if (!didPop) return;
    _nav.fine('categories closed by $_closedBy');
  }

  void _add(String budgetId) {
    _log.fine(
      'categories add tap budgetId=$budgetId → ${AppRoutes.newCategory}',
    );
    context.push(AppRoutes.newCategory);
  }

  void _open(Category category, int index) {
    _log.fine(
      'category row #$index tap id=${category.id} → '
      '${AppRoutes.category}',
    );
    context.push(AppRoutes.categoryOf(category.id));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final budgetValue = ref.watch(selectedBudgetIdProvider);
    final budgetId = budgetValue.value;
    final Widget body;
    if (budgetId == null) {
      body = budgetValue.isLoading
          ? const SizedBox.shrink()
          : _ListBody(rows: const [], hint: l10n.categoriesOrderHint);
    } else {
      final categories = ref.watch(categoriesProvider(budgetId));
      final countsValue = ref.watch(categoryExpenseCountsProvider(budgetId));
      if (!identical(categories, _loggedCategories)) {
        _loggedCategories = categories;
        _logCategories(budgetId, categories);
      }
      if (!identical(countsValue, _loggedCounts)) {
        _loggedCounts = countsValue;
        _logCounts(budgetId, countsValue);
      }
      final counts = countsValue.hasError ? null : countsValue.value;
      switch (categories) {
        case AsyncError():
          body = _LoadFailed(text: l10n.categoriesLoadFailed);
        case AsyncData(value: final list):
          body = _ListBody(
            hint: l10n.categoriesOrderHint,
            rows: [
              for (final (i, category) in list.indexed)
                category.isSystem
                    ? _CategoryRow(
                        category: category,
                        subtitle: l10n.categoriesOtherHint,
                      )
                    : _CategoryRow(
                        category: category,
                        subtitle: counts == null
                            ? null
                            : l10n.categoriesExpenses(counts[category.id] ?? 0),
                        onTap: () => _open(category, i),
                      ),
            ],
          );
        default:
          body = const SizedBox.shrink();
      }
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
              child: CategoriesTopBar(
                title: l10n.categoriesTitle,
                onBack: _back,
                addLabel: l10n.categoryNewTitle,
                onAdd: budgetId == null ? null : () => _add(budgetId),
              ),
            ),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}

class _ListBody extends StatelessWidget {
  const _ListBody({required this.rows, required this.hint});

  final List<Widget> rows;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(12, 4, 12, 24 + bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (rows.isNotEmpty) ...[
            Material(
              color: colors.bgSurface,
              borderRadius: BorderRadius.circular(RadiusTokens.lg),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: rows,
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          Text(
            hint,
            style: AppText.caption.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.category,
    required this.subtitle,
    this.onTap,
  });

  final Category category;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = subtitle;
    return Semantics(
      button: onTap != null,
      label: text == null ? category.name : '${category.name}, $text',
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 60),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
            child: Row(
              children: [
                CategoryBadge(emoji: category.emoji, color: category.color),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FittingText(
                        category.name,
                        style: AppText.labelM.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                      if (text != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          text,
                          style: AppText.caption.copyWith(
                            color: colors.textTertiary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (onTap != null) ...[
                  const SizedBox(width: 12),
                  AppIcon(
                    AppIcons.chevronRight,
                    size: 18,
                    color: colors.textTertiary,
                  ),
                ],
              ],
            ),
          ),
        ),
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
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: FittingText(
          text,
          textAlign: TextAlign.center,
          style: AppText.bodyM.copyWith(color: colors.textSecondary),
        ),
      ),
    );
  }
}
