import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import '../../core/clock.dart';
import '../../ui/components/month_card.dart';
import 'day_sheet.dart';
import 'month_controller.dart';
import 'month_header.dart';
import 'month_picker_sheet.dart';

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
  bool _pickerOpen = false;
  LocalDate? _sheetDay;

  @override
  void initState() {
    super.initState();
    _log.fine(
      'month screen opened month=${ref.read(monthControllerProvider)} '
      'today=${ref.read(clockProvider).today()}',
    );
  }

  MonthController get _controller => ref.read(monthControllerProvider.notifier);

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
    if (_pickerOpen) {
      _log.fine('month title tap month=$month ignored: picker already open');
      return;
    }
    _log.fine('month title tap month=$month → month picker');
    _pickerOpen = true;
    final YearMonth? chosen;
    try {
      chosen = await showMonthPickerSheet(context, shown: month);
    } finally {
      _pickerOpen = false;
    }
    if (chosen == null) return;
    if (!mounted) {
      _log.warning(
        'month picker chose $chosen but month screen is gone, nothing to show',
      );
      return;
    }
    _controller.open(chosen);
  }

  Future<void> _openDay(LocalDate date) async {
    final today = ref.read(clockProvider).today();
    if (dayKind(date, today) == DayKind.future) {
      _log.fine('day tap date=$date ignored: future day today=$today');
      return;
    }
    final open = _sheetDay;
    if (open != null) {
      _log.fine('day tap date=$date ignored: day sheet of $open is open');
      return;
    }
    _log.fine('day tap date=$date → day sheet');
    setState(() => _sheetDay = date);
    try {
      await showDaySheet(context, day: date);
    } finally {
      if (mounted) setState(() => _sheetDay = null);
    }
  }

  void _openCatalog() {
    _log.info('long press on month header → debug catalog');
    context.pushNamed('catalog');
  }

  @override
  Widget build(BuildContext context) {
    final today = ref.watch(clockProvider).today();
    final requested = ref.watch(monthControllerProvider);
    final shown = ref.watch(shownMonthProvider);
    final data = shown.hasError ? null : shown.value;
    final bottom = MediaQuery.paddingOf(context).bottom;

    Widget? card;
    if (data != null || shown.hasError) {
      final month = data?.month ?? requested;
      card = MonthCard(
        month: month,
        today: today,
        dayTotals: data?.dayTotals ?? const {},
        mood: Mood.ofSeason(seasonOf(month.month)),
        holidayMarks: monthMarkEmojis(month),
        selectedDay: _sheetDay != null && month.contains(_sheetDay!)
            ? _sheetDay!.day
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
              onLongPress: kDebugMode ? _openCatalog : null,
              child: const MonthHeader(),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(12, 6, 12, 20 + bottom),
                child: card ?? const SizedBox.shrink(),
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
