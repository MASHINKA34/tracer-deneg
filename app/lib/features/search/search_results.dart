import 'package:flutter/material.dart';
import 'package:shared/shared.dart';

import '../../data/queries/search_queries.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/components/button.dart';
import '../../ui/components/fitting_text.dart';
import '../../ui/theme/app_text.dart';
import '../../ui/theme/app_theme.dart';
import '../../ui/tokens/tokens.g.dart';
import '../budgets/expense_authors.dart' show ExpenseAuthorView;
import '../expense/expense_swipe_to_delete.dart';
import '../month/day_sheet.dart' show DayExpenseRow;
import 'search_period.dart';

const double _side = 12;

const double _gap = 8;

class SearchFilterChips extends StatelessWidget {
  const SearchFilterChips({super.key, required this.chips});

  final List<Widget> chips;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: _side),
        child: Row(
          children: [
            for (final (i, chip) in chips.indexed) ...[
              if (i > 0) const SizedBox(width: _gap),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: constraints.maxWidth - 2 * _side,
                ),
                child: chip,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class SearchResults extends StatelessWidget {
  const SearchResults({
    super.key,
    required this.result,
    required this.today,
    required this.categoryOf,
    required this.onOpen,
    this.authorOf,
  });

  final SearchResult result;
  final LocalDate today;
  final Category? Function(Expense expense) categoryOf;
  final ValueChanged<Expense> onOpen;
  final ExpenseAuthorView? Function(Expense expense)? authorOf;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final days = groupSearchResults(result.expenses);
    final bottom = MediaQuery.viewPaddingOf(context).bottom;
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(_side, 6, _side, 16 + bottom),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: days.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return FittingText(
            l10n.searchFound(result.count, result.total.formatTotal()),
            style: AppText.labelS.copyWith(color: colors.textTertiary),
          );
        }
        final day = days[index - 1];
        return Padding(
          key: ValueKey<LocalDate>(day.day),
          padding: const EdgeInsets.only(top: _gap),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: FittingText(
                  searchDayTitle(day.day, today),
                  style: AppText.labelS.copyWith(color: colors.textSecondary),
                ),
              ),
              const SizedBox(height: _gap),
              Material(
                color: colors.bgSurface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(RadiusTokens.lg),
                ),
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Column(
                    children: [
                      for (final expense in day.expenses)
                        ExpenseSwipeToDelete(
                          key: ValueKey<String>(expense.id),
                          expense: expense,
                          from: 'search',
                          child: DayExpenseRow(
                            expense: expense,
                            category: categoryOf(expense),
                            author: authorOf?.call(expense),
                            onTap: () => onOpen(expense),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class SearchEmpty extends StatelessWidget {
  const SearchEmpty({super.key, required this.onReset});

  final VoidCallback onReset;

  static const String _emoji = '🔍';

  static const double _circle = 88;

  static const double _top = 122;

  static const double _side = 32;

  static const double _gap = 10;

  static const double _buttonSlack = (kMinInteractiveDimension - 40) / 2;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final mood = context.mood;
    final bottom = MediaQuery.viewPaddingOf(context).bottom;
    return ListView(
      padding: EdgeInsets.fromLTRB(_side, _top, _side, 24 + bottom),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        Center(
          child: ExcludeSemantics(
            child: Container(
              width: _circle,
              height: _circle,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: mood.soft,
                shape: BoxShape.circle,
              ),
              child: Text(
                _emoji,
                textScaler: TextScaler.noScaling,
                style: AppText.displayL.copyWith(color: colors.textPrimary),
              ),
            ),
          ),
        ),
        const SizedBox(height: _gap),
        Semantics(
          header: true,
          child: FittingText(
            l10n.searchEmptyTitle,
            textAlign: TextAlign.center,
            style: AppText.titleM.copyWith(color: colors.textPrimary),
          ),
        ),
        const SizedBox(height: _gap),
        FittingText(
          l10n.searchEmptyText,
          textAlign: TextAlign.center,
          style: AppText.bodyM.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: _gap - _buttonSlack),
        Center(
          child: AppButton(
            label: l10n.searchEmptyReset,
            onPressed: onReset,
            type: AppButtonType.outline,
            size: AppButtonSize.m,
          ),
        ),
      ],
    );
  }
}

class SearchFailed extends StatelessWidget {
  const SearchFailed({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 48, 32, 0),
      child: FittingText(
        AppLocalizations.of(context).searchFailed,
        textAlign: TextAlign.center,
        style: AppText.bodyM.copyWith(color: context.colors.textSecondary),
      ),
    );
  }
}
