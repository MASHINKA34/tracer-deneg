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
import '../../ui/components/chip.dart';
import '../../ui/icons/app_icon.dart';
import '../../ui/theme/app_text.dart';
import '../../ui/theme/app_theme.dart';
import '../month/month_picker_sheet.dart' show monthTitle;

final _log = Logger('nav');

String searchPeriodLabel(AppLocalizations l10n, LocalDate from, LocalDate to) {
  final month = from.yearMonth;
  if (from == month.firstDay && to == month.lastDay) return monthTitle(month);
  final format = DateFormat('dd.MM.yyyy', 'ru');
  String date(LocalDate d) => format.format(DateTime(d.year, d.month, d.day));
  return l10n.searchFilterPeriod(date(from), date(to));
}

class SearchStubScreen extends ConsumerStatefulWidget {
  const SearchStubScreen({super.key, this.query = const {}});

  final Map<String, String> query;

  @override
  ConsumerState<SearchStubScreen> createState() => _SearchStubScreenState();
}

class _SearchStubScreenState extends ConsumerState<SearchStubScreen> {
  bool _backTapped = false;
  late final SearchRouteFilter _filter;

  @override
  void initState() {
    super.initState();
    _filter = SearchRouteFilter.fromQuery(widget.query);
    if (_filter.isEmpty) {
      _log.fine('search opened without filter');
    } else {
      _log.fine('search opened with filter $_filter');
    }
    final categoryId = _filter.categoryId;
    if (categoryId != null) {
      ref.listenManual(
        categoryProvider(categoryId),
        (previous, next) => _onCategory(categoryId, next),
        fireImmediately: true,
      );
    }
  }

  void _onCategory(String categoryId, AsyncValue<Category?> next) {
    switch (next) {
      case AsyncData(value: null):
        _log.warning(
          'search filter category=$categoryId not found among live '
          'categories, filter chip hidden',
        );
      case AsyncError(:final error, :final stackTrace):
        var cause = error;
        while (cause is ProviderException) {
          cause = cause.exception;
        }
        final redacted = redactDbError(cause);
        _log.severe(
          'search filter category=$categoryId failed to load, filter chip '
          'hidden: ${describeError(redacted)}',
          redacted,
          stackTrace,
        );
      default:
    }
  }

  void _back() {
    _backTapped = true;
    context.pop();
  }

  void _handlePop(bool didPop, Object? result) {
    if (!didPop) return;
    _log.fine('search closed by ${_backTapped ? 'back button' : 'back'}');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final categoryId = _filter.categoryId;
    final from = _filter.from;
    final to = _filter.to;
    final categoryValue = categoryId == null
        ? null
        : ref.watch(categoryProvider(categoryId));
    final category = categoryValue == null || categoryValue.hasError
        ? null
        : categoryValue.value;
    return PopScope<Object?>(
      onPopInvokedWithResult: _handlePop,
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 56),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
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
                      Expanded(
                        child: Semantics(
                          header: true,
                          child: Text(
                            l10n.searchTitle,
                            textAlign: TextAlign.center,
                            style: AppText.titleS.copyWith(
                              color: colors.textPrimary,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 48),
                    ],
                  ),
                ),
              ),
              if (category != null || (from != null && to != null))
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      if (category != null)
                        AppChip(
                          emoji: category.emoji,
                          label: category.name,
                          selected: true,
                        ),
                      if (from != null && to != null)
                        AppChip(
                          label: searchPeriodLabel(l10n, from, to),
                          selected: true,
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
