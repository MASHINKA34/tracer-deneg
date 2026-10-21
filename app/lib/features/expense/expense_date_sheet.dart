import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import '../../core/clock.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/components/button.dart';
import '../../ui/components/chip.dart';
import '../../ui/components/fitting_text.dart';
import '../../ui/components/sheet.dart';
import '../../ui/components/tap_target.dart';
import '../../ui/icons/app_icon.dart';
import '../../ui/theme/app_text.dart';
import '../../ui/theme/app_theme.dart';
import '../month/month_picker_sheet.dart' show monthTitle;

final _log = Logger('expense');

const double expenseDateDayHeight = 36;

const double expenseDateGap = 4;

const double _blockGap = 14;

const double _sheetGap = 16;

const double _headHeight = 32;

const double _chipHeight = 36;

const double _chipPadding = 16;

double _scaledLine(TextScaler scaler, TextStyle style) =>
    scaler.scale(style.fontSize!) * style.height!;

double tapSlack(double visual) => math.max(0, (kMinTapTarget - visual) / 2);

double chipTapSlack(TextScaler scaler) => tapSlack(
  math.max(_chipHeight, _scaledLine(scaler, AppText.labelM) + _chipPadding),
);

double sheetTitleLift(TextScaler scaler, {double visual = 0}) =>
    _sheetGap -
    _blockGap +
    tapSlack(math.max(visual, _scaledLine(scaler, AppText.titleM)));

enum QuickExpenseDate { today, yesterday, dayBefore }

LocalDate quickExpenseDate(QuickExpenseDate quick, LocalDate today) =>
    today.addDays(-quick.index);

double expenseDateDayHeightFor(TextScaler scaler) {
  final style = AppText.labelM;
  final line = style.fontSize! * style.height!;
  final scaled = scaler.scale(style.fontSize!) * style.height!;
  return math.max(expenseDateDayHeight, expenseDateDayHeight - line + scaled);
}

Future<LocalDate?> showExpenseDateSheet(
  BuildContext context, {
  required LocalDate initial,
}) async {
  final sw = Stopwatch()..start();
  final root = Navigator.of(context, rootNavigator: true);
  _log.fine('date sheet opened initial=$initial');
  final chosen = await showAppSheet<LocalDate>(
    root.context,
    builder: (context) => [ExpenseDateSheet(initial: initial)],
  );
  if (chosen == null) {
    _log.fine(
      'date sheet closed without choice after ${sw.elapsedMilliseconds}ms: '
      'back gesture, tap outside or swipe down, date stays $initial',
    );
  } else {
    _log.fine('date sheet done date=$chosen after ${sw.elapsedMilliseconds}ms');
  }
  return chosen;
}

class ExpenseDateSheet extends ConsumerStatefulWidget {
  const ExpenseDateSheet({super.key, required this.initial});

  final LocalDate initial;

  @override
  ConsumerState<ExpenseDateSheet> createState() => _ExpenseDateSheetState();
}

class _ExpenseDateSheetState extends ConsumerState<ExpenseDateSheet> {
  late LocalDate _selected;
  late YearMonth _shown;

  @override
  void initState() {
    super.initState();
    final today = ref.read(clockProvider).today();
    var initial = widget.initial;
    if (initial.isAfter(today)) {
      _log.warning(
        'date sheet initial=$initial is in the future today=$today, '
        'selecting today instead',
      );
      initial = today;
    }
    _selected = initial;
    _shown = YearMonth.of(initial);
    _log.fine(
      'date sheet shows month=$_shown selected=$_selected today=$today',
    );
  }

  void _showMonth(int delta) {
    final today = ref.read(clockProvider).today();
    final from = _shown;
    if (delta < 0 && from == YearMonth(1, 1)) {
      _log.fine('date sheet month $from → previous ignored: no earlier months');
      return;
    }
    final to = from.addMonths(delta);
    if (isFutureMonth(to, today)) {
      _log.fine(
        'date sheet month $from → $to ignored: future month today=$today',
      );
      return;
    }
    setState(() => _shown = to);
    _log.fine('date sheet month $from → $to by=arrow selected=$_selected');
  }

  void _select(LocalDate date, {required String by}) {
    final today = ref.read(clockProvider).today();
    if (date.isAfter(today)) {
      _log.fine('date sheet $by $date ignored: future day today=$today');
      return;
    }
    final from = _selected;
    setState(() {
      _selected = date;
      _shown = YearMonth.of(date);
    });
    _log.fine('date sheet selected $from → $date by=$by');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final today = ref.watch(clockProvider).today();
    final quick = [
      (QuickExpenseDate.today, l10n.expenseDateToday),
      (QuickExpenseDate.yesterday, l10n.expenseDateYesterday),
      (QuickExpenseDate.dayBefore, l10n.expenseDateDayBefore),
    ];

    final scaler = MediaQuery.textScalerOf(context);
    final headSlack = tapSlack(
      math.max(_headHeight, _scaledLine(scaler, AppText.titleM)),
    );
    final chipSlack = chipTapSlack(scaler);

    return Flexible(
      child: Transform.translate(
        offset: Offset(0, -sheetTitleLift(scaler, visual: _headHeight)),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Head(
                month: _shown,
                onPrevious: _shown == YearMonth(1, 1)
                    ? null
                    : () => _showMonth(-1),
                onNext: canGoToNextMonth(_shown, today)
                    ? () => _showMonth(1)
                    : null,
              ),
              SizedBox(height: _blockGap - headSlack - chipSlack),
              Wrap(
                spacing: 8,
                runSpacing: 8 - 2 * chipSlack,
                children: [
                  for (final (kind, label) in quick)
                    AppChip(
                      label: label,
                      selected: _selected == quickExpenseDate(kind, today),
                      onTap: () =>
                          _select(quickExpenseDate(kind, today), by: kind.name),
                    ),
                ],
              ),
              SizedBox(height: _blockGap - chipSlack),
              const _Weekdays(),
              const SizedBox(height: _blockGap - expenseDateGap / 2),
              _Grid(
                month: _shown,
                today: today,
                selected: _selected,
                onTap: (date) => _select(date, by: 'calendar'),
              ),
              const SizedBox(height: _blockGap - expenseDateGap / 2),
              AppButton(
                label: l10n.expenseSheetDone,
                expand: true,
                onPressed: () => Navigator.of(context).pop(_selected),
              ),
              const SizedBox(height: _blockGap),
              FittingText(
                l10n.expenseDateFutureHint,
                textAlign: TextAlign.center,
                style: AppText.caption.copyWith(color: colors.textTertiary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Head extends StatelessWidget {
  const _Head({required this.month, this.onPrevious, this.onNext});

  final YearMonth month;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  static const double _gap = 4;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Semantics(
          header: true,
          child: FittingText(
            l10n.expenseDateTitle,
            style: AppText.titleM.copyWith(color: colors.textPrimary),
          ),
        ),
        Stack(
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: kMinTapTarget),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: _NavButton.size + _gap,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: FittingText(
                        monthTitle(month),
                        style: AppText.labelM.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: _NavButton(
                icon: AppIcons.chevronLeft,
                label: l10n.a11yPrevMonth,
                alignment: Alignment.centerLeft,
                onTap: onPrevious,
              ),
            ),
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              child: _NavButton(
                icon: AppIcons.chevronRight,
                label: l10n.a11yNextMonth,
                alignment: Alignment.centerRight,
                onTap: onNext,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.icon,
    required this.label,
    required this.alignment,
    this.onTap,
  });

  final AppIcons icon;
  final String label;
  final Alignment alignment;
  final VoidCallback? onTap;

  static const double size = 32;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final enabled = onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: kMinTapTarget,
          alignment: alignment,
          child: Material(
            color: colors.bgSurface2,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: SizedBox.square(
                dimension: size,
                child: Center(
                  child: AppIcon(
                    icon,
                    size: 18,
                    color: enabled ? colors.textPrimary : colors.textDisabled,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Weekdays extends StatelessWidget {
  const _Weekdays();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final monday = DateTime(2024, 1, 1);
    final format = DateFormat.E('ru');
    return ExcludeSemantics(
      child: Row(
        children: [
          for (var i = 0; i < 7; i++) ...[
            if (i > 0) const SizedBox(width: expenseDateGap),
            Expanded(
              child: Text(
                format.format(monday.add(Duration(days: i))),
                textAlign: TextAlign.center,
                style: AppText.labelS.copyWith(color: colors.textTertiary),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({
    required this.month,
    required this.today,
    required this.selected,
    required this.onTap,
  });

  final YearMonth month;
  final LocalDate today;
  final LocalDate selected;
  final ValueChanged<LocalDate> onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final height = expenseDateDayHeightFor(MediaQuery.textScalerOf(context));
    final format = DateFormat('d MMMM', 'ru');
    const half = expenseDateGap / 2;

    String label(LocalDate date) {
      final text = format.format(DateTime(date.year, date.month, date.day));
      return [
        if (date.isAfter(today)) l10n.a11yDayFuture(text) else text,
        if (date == today) l10n.a11yDayToday,
        if (date == selected) l10n.a11yDaySelected,
      ].join(', ');
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final cell = (constraints.maxWidth - 6 * expenseDateGap) / 7;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final week in monthGrid(month))
              Row(
                children: [
                  for (final (i, date) in week.indexed)
                    SizedBox(
                      width: cell + (i == 0 ? 0 : half) + (i == 6 ? 0 : half),
                      child: date == null
                          ? SizedBox(height: height + expenseDateGap)
                          : _Day(
                              date: date,
                              height: height,
                              padding: EdgeInsets.fromLTRB(
                                i == 0 ? 0 : half,
                                half,
                                i == 6 ? 0 : half,
                                half,
                              ),
                              selected: date == selected,
                              future: date.isAfter(today),
                              label: label(date),
                              onTap: () => onTap(date),
                            ),
                    ),
                ],
              ),
          ],
        );
      },
    );
  }
}

class _Day extends StatelessWidget {
  const _Day({
    required this.date,
    required this.height,
    required this.padding,
    required this.selected,
    required this.future,
    required this.label,
    required this.onTap,
  });

  final LocalDate date;
  final double height;
  final EdgeInsets padding;
  final bool selected;
  final bool future;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final mood = context.mood;
    final color = selected
        ? mood.onAccent
        : future
        ? colors.textDisabled
        : colors.textPrimary;
    return Semantics(
      button: !future,
      enabled: !future,
      selected: selected,
      label: label,
      excludeSemantics: true,
      onTap: future ? null : onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTap: future ? null : onTap,
        child: Padding(
          padding: padding,
          child: Container(
            height: height,
            decoration: selected
                ? BoxDecoration(
                    color: mood.accent,
                    borderRadius: BorderRadius.circular(height / 2),
                  )
                : null,
            alignment: Alignment.center,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '${date.day}',
                maxLines: 1,
                style: AppText.labelM.copyWith(color: color),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
