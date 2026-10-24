import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import '../../core/clock.dart';
import '../../data/api/api_exception.dart';
import '../../data/sync/budget_removed_notice.dart';
import '../../data/sync/pull_controller.dart';
import '../../data/sync/pull_service.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/components/month_card.dart';
import '../../ui/components/snackbar.dart';
import '../../ui/theme/app_theme.dart';
import '../expense/expense_snackbar_layer.dart';
import '../holidays/holiday_banner_controller.dart';
import '../holidays/holiday_banner_slot.dart';
import '../holidays/mood_controller.dart';
import 'day_sheet.dart';
import 'month_controller.dart';
import 'month_header.dart';
import 'month_picker_sheet.dart';
import 'today_block.dart';

final _log = Logger('month');

const Duration monthSlideDuration = Duration(milliseconds: 250);

const double monthSwipeDistance = 48;

const double monthSwipeVelocity = 300;

class MonthScreen extends ConsumerStatefulWidget {
  const MonthScreen({super.key});

  @override
  ConsumerState<MonthScreen> createState() => _MonthScreenState();
}

class _MonthScreenState extends ConsumerState<MonthScreen> {
  double _dragDx = 0;

  @override
  void initState() {
    super.initState();
    _log.fine(
      'month screen opened month=${ref.read(monthControllerProvider)} '
      'today=${ref.read(clockProvider).today()}',
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _onPull(null, ref.read(pullControllerProvider));
      _onBudgetRemoved(null, ref.read(budgetRemovedNoticeProvider));
    });
  }

  MonthController get _controller => ref.read(monthControllerProvider.notifier);

  PullController get _pull => ref.read(pullControllerProvider.notifier);

  void _onPull(PullStatus? previous, PullStatus next) {
    switch (next) {
      case PullPending():
        Future.microtask(() {
          if (mounted) _pull.startRequested();
        });
      case PullFailed(:final id, :final failure)
          when failure.error is ApiSessionExpired &&
              _pull.claimFailureNotice(id):
        _log.info(
          'pull failed #$id reason=${failure.reason.name} '
          '${failure.errorType}: session ended → sign-in screen, no retry '
          'snackbar, data on the phone kept',
        );
      case PullFailed(:final id, :final failure)
          when _pull.claimFailureNotice(id):
        _log.info(
          'pull failed #$id reason=${failure.reason.name} '
          '${failure.errorType} → snackbar with retry, data on the phone kept',
        );
        Future.microtask(() {
          if (mounted) _showPullFailed();
        });
      default:
    }
  }

  void _onBudgetRemoved(
    BudgetRemovedNotice? previous,
    BudgetRemovedNotice? next,
  ) {
    if (next == null ||
        !ref.read(budgetRemovedNoticeProvider.notifier).claim(next.id)) {
      return;
    }
    _log.info(
      'budget removed notice #${next.id} budgetId=${next.budgetId} '
      'kind=${next.kind.name} → snackbar, personal budget shown',
    );
    Future.microtask(() {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      showAppSnackbar(
        context,
        text: switch (next.kind) {
          BudgetRemovalKind.excluded => l10n.budgetRemovedExcluded(next.name),
          BudgetRemovalKind.deleted => l10n.budgetRemovedDeleted(next.name),
        },
        margin: const EdgeInsets.fromLTRB(
          expenseSnackbarSide,
          0,
          expenseSnackbarSide,
          expenseSnackbarAboveAnchor,
        ),
      );
    });
  }

  void _showPullFailed() {
    final l10n = AppLocalizations.of(context);
    showAppSnackbar(
      context,
      text: l10n.pullFailed,
      actionLabel: l10n.pullRetry,
      margin: const EdgeInsets.fromLTRB(
        expenseSnackbarSide,
        0,
        expenseSnackbarSide,
        expenseSnackbarAboveAnchor,
      ),
      onAction: () {
        _log.info('pull retry tap on snackbar → pull reason=retry');
        _pull.run(PullReason.retry);
      },
    );
  }

  Future<void> _onRefresh() async {
    _log.fine('month pulled down → pull reason=manual');
    await _pull.run(PullReason.manual);
  }

  void _onDragEnd(DragEndDetails details) {
    final dx = _dragDx;
    final velocity = details.primaryVelocity ?? 0;
    _dragDx = 0;
    final bool forward;
    if (velocity.abs() >= monthSwipeVelocity) {
      forward = velocity < 0;
    } else if (dx.abs() >= monthSwipeDistance) {
      forward = dx < 0;
    } else {
      _log.fine(
        'month swipe ignored dx=${dx.round()} '
        'velocity=${velocity.round()}: shorter than '
        '${monthSwipeDistance.round()}px and slower than '
        '${monthSwipeVelocity.round()}px/s',
      );
      return;
    }
    if (forward) {
      _controller.next(MonthStepSource.swipe);
    } else {
      _controller.previous(MonthStepSource.swipe);
    }
  }

  Future<void> _openPicker(YearMonth month) async {
    final container = ProviderScope.containerOf(context, listen: false);
    if (!container.read(monthPickerOpenProvider.notifier).open()) {
      _log.fine('month title tap month=$month ignored: picker already open');
      return;
    }
    _log.fine('month title tap month=$month → month picker');
    final YearMonth? chosen;
    try {
      chosen = await showMonthPickerSheet(context, shown: month);
    } finally {
      container.read(monthPickerOpenProvider.notifier).close();
    }
    if (chosen == null) return;
    if (!mounted) {
      _log.fine(
        'month picker chose $chosen after month screen left the tree, '
        'opening it in the month controller anyway',
      );
    }
    container.read(monthControllerProvider.notifier).open(chosen);
  }

  Future<void> _openDay(LocalDate date) async {
    final today = ref.read(clockProvider).today();
    if (dayKind(date, today) == DayKind.future) {
      _log.fine('day tap date=$date ignored: future day today=$today');
      return;
    }
    final container = ProviderScope.containerOf(context, listen: false);
    if (!container.read(openDaySheetProvider.notifier).open(date)) {
      _log.fine(
        'day tap date=$date ignored: day sheet of '
        '${container.read(openDaySheetProvider)} is open',
      );
      return;
    }
    _log.fine('day tap date=$date → day sheet');
    try {
      await showDaySheet(context, day: date);
    } finally {
      container.read(openDaySheetProvider.notifier).close(date);
    }
  }

  void _logTodayBlock(YearMonth? previous, YearMonth next) {
    final current = YearMonth.of(ref.read(clockProvider).today());
    if (previous == current && next != current) {
      _log.fine(
        'today block hidden month=$next: not the current month $current',
      );
    } else if (previous != null && previous != current && next == current) {
      _log.fine('today block shown again month=$next: current month');
    }
  }

  void _openCatalog() {
    _log.info('long press on month header → debug catalog');
    context.pushNamed('catalog');
  }

  @override
  Widget build(BuildContext context) {
    final today = ref.watch(clockProvider).today();
    ref.listen(monthControllerProvider, _logTodayBlock);
    ref.listen(pullControllerProvider, _onPull);
    ref.listen<BudgetRemovedNotice?>(
      budgetRemovedNoticeProvider,
      _onBudgetRemoved,
    );
    final requested = ref.watch(monthControllerProvider);
    final shown = ref.watch(shownMonthProvider);
    final sheetDay = ref.watch(openDaySheetProvider);
    final moodToday = ref.watch(moodControllerProvider);
    final data = shown.hasError ? null : shown.value;
    final bottom = MediaQuery.paddingOf(context).bottom;

    Widget? card;
    var current = false;
    HolidayPhase? banner;
    if (data != null || shown.hasError) {
      final month = data?.month ?? requested;
      current = month == YearMonth.of(today);
      if (current) banner = ref.watch(holidayBannerProvider);
      card = MonthCard(
        month: month,
        today: today,
        dayTotals: data?.dayTotals ?? const {},
        mood: monthCardMood(month, moodToday),
        holidayMarks: monthMarkEmojis(
          month,
          birthday: moodToday.settings.birthday,
        ),
        selectedDay: sheetDay != null && month.contains(sheetDay)
            ? sheetDay.day
            : null,
        onMonthTap: () => _openPicker(month),
        onPrevious: () => _controller.previous(MonthStepSource.arrow),
        onNext: canGoToNextMonth(month, today)
            ? () => _controller.next(MonthStepSource.arrow)
            : null,
        onDayTap: (day) => _openDay(month.dayOf(day)),
      );
      card = GestureDetector(
        dragStartBehavior: DragStartBehavior.down,
        onHorizontalDragStart: (_) => _dragDx = 0,
        onHorizontalDragUpdate: (details) => _dragDx += details.delta.dx,
        onHorizontalDragEnd: _onDragEnd,
        child: _MonthSlide(month: month, child: card),
      );
    }

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              excludeFromSemantics: true,
              onLongPress: kDebugMode ? _openCatalog : null,
              child: const MonthHeader(),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _onRefresh,
                color: context.mood.accentStrong,
                backgroundColor: context.colors.bgSurface,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(12, 6, 12, 20 + bottom),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (banner != null) ...[
                        HolidayBannerSlot(phase: banner),
                        const SizedBox(height: 14),
                      ],
                      ?card,
                      if (current) ...[
                        SizedBox(height: banner == null ? 20 : 14),
                        TodayBlock(today: today),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthSlide extends StatefulWidget {
  const _MonthSlide({required this.month, required this.child});

  final YearMonth month;
  final Widget child;

  @override
  State<_MonthSlide> createState() => _MonthSlideState();
}

class _MonthSlideState extends State<_MonthSlide> {
  int _direction = 1;

  @override
  void didUpdateWidget(covariant _MonthSlide oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.month != widget.month) {
      _direction = widget.month > oldWidget.month ? 1 : -1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = ValueKey<YearMonth>(widget.month);
    return AnimatedSwitcher(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : monthSlideDuration,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeOutCubic.flipped,
      layoutBuilder: (currentChild, previousChildren) => Stack(
        alignment: Alignment.topCenter,
        children: [...previousChildren, ?currentChild],
      ),
      transitionBuilder: (child, animation) {
        final side = child.key == current ? _direction : -_direction;
        return SlideTransition(
          position: Tween<Offset>(
            begin: Offset(side.toDouble(), 0),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        );
      },
      child: KeyedSubtree(key: current, child: widget.child),
    );
  }
}
