import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import '../../core/clock.dart';
import '../../ui/components/month_card.dart';
import 'month_controller.dart';
import 'month_header.dart';

final _log = Logger('month');

class MonthScreen extends ConsumerStatefulWidget {
  const MonthScreen({super.key});

  @override
  ConsumerState<MonthScreen> createState() => _MonthScreenState();
}

class _MonthScreenState extends ConsumerState<MonthScreen> {
  @override
  void initState() {
    super.initState();
    _log.fine(
      'month screen opened month=${ref.read(monthControllerProvider)} '
      'today=${ref.read(clockProvider).today()}',
    );
  }

  MonthController get _controller => ref.read(monthControllerProvider.notifier);

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
        onMonthTap: () => _log.fine(
          'month title tap month=$month: no action, month picker is not '
          'available yet',
        ),
        onPrevious: () => _controller.previous(MonthStepSource.arrow),
        onNext: canGoToNextMonth(month, today)
            ? () => _controller.next(MonthStepSource.arrow)
            : null,
        onDayTap: (day) => _log.fine(
          'day tap date=${month.dayOf(day)}: no action, day sheet is not '
          'available yet',
        ),
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
