import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/components/button.dart';
import '../../ui/components/fitting_text.dart';
import '../../ui/components/sheet.dart';
import '../../ui/components/tap_target.dart';
import '../../ui/theme/app_text.dart';
import '../../ui/theme/app_theme.dart';
import '../../ui/tokens/tokens.g.dart';

final _log = Logger('recurring');

const int recurringDayCount = 31;

const int recurringDayMaxColumns = 7;

const double recurringDayInset = 2;

int recurringDayColumns(double width) => math.max(
  1,
  math.min(recurringDayMaxColumns, (width / kMinTapTarget).floor()),
);

Future<int?> showRecurringDaySheet(
  BuildContext context, {
  required int initial,
}) async {
  final sw = Stopwatch()..start();
  final root = Navigator.of(context, rootNavigator: true);
  _log.fine('day sheet opened day=$initial');
  final chosen = await showAppSheet<int>(
    root.context,
    builder: (context) => [RecurringDaySheet(initial: initial)],
  );
  if (chosen == null) {
    _log.fine(
      'day sheet closed without done after ${sw.elapsedMilliseconds}ms: '
      'back gesture, tap outside or swipe down, day stays $initial',
    );
  } else {
    _log.fine('day sheet done day=$chosen after ${sw.elapsedMilliseconds}ms');
  }
  return chosen;
}

class RecurringDaySheet extends StatefulWidget {
  const RecurringDaySheet({super.key, required this.initial});

  final int initial;

  @override
  State<RecurringDaySheet> createState() => _RecurringDaySheetState();
}

class _RecurringDaySheetState extends State<RecurringDaySheet> {
  late int _selected = _initial();

  int _initial() {
    final day = widget.initial;
    if (day >= 1 && day <= recurringDayCount) return day;
    _log.warning('day sheet initial day=$day is out of 1–31, selecting 1');
    return 1;
  }

  void _select(int day) {
    if (day == _selected) {
      _log.fine('day sheet day=$day tapped again, already selected');
      return;
    }
    final from = _selected;
    setState(() => _selected = day);
    _log.fine('day sheet selected $from → $day');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    return Flexible(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: FittingText(
                l10n.recurringEditorDay,
                style: AppText.titleM.copyWith(color: colors.textPrimary),
              ),
            ),
            const SizedBox(height: 16 - recurringDayInset),
            _DayGrid(selected: _selected, onTap: _select),
            const SizedBox(height: 16 - recurringDayInset),
            AppButton(
              label: l10n.expenseSheetDone,
              expand: true,
              onPressed: () => Navigator.of(context).pop(_selected),
            ),
          ],
        ),
      ),
    );
  }
}

class _DayGrid extends StatelessWidget {
  const _DayGrid({required this.selected, required this.onTap});

  final int selected;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final style = AppText.labelM;
    final height = math.max(
      kMinTapTarget,
      scaler.scale(style.fontSize!) * style.height! + 2 * 12,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = recurringDayColumns(constraints.maxWidth);
        final width = constraints.maxWidth / columns;
        final rows = (recurringDayCount / columns).ceil();
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var row = 0; row < rows; row++)
              Row(
                children: [
                  for (var column = 0; column < columns; column++)
                    SizedBox(
                      width: width,
                      height: height,
                      child: row * columns + column < recurringDayCount
                          ? _DayCell(
                              day: row * columns + column + 1,
                              selected: row * columns + column + 1 == selected,
                              onTap: onTap,
                            )
                          : null,
                    ),
                ],
              ),
          ],
        );
      },
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.selected,
    required this.onTap,
  });

  final int day;
  final bool selected;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final mood = context.mood;
    final radius = BorderRadius.circular(RadiusTokens.sm);
    return Semantics(
      button: true,
      selected: selected,
      label: [
        l10n.recurringEditorDayValue(day),
        if (selected) l10n.a11yDaySelected,
      ].join(', '),
      excludeSemantics: true,
      onTap: () => onTap(day),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTap: () => onTap(day),
        child: Padding(
          padding: const EdgeInsets.all(recurringDayInset),
          child: Material(
            color: selected ? mood.accent : colors.bgSurface2,
            borderRadius: radius,
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '$day',
                  maxLines: 1,
                  style: AppText.labelM.copyWith(
                    color: selected ? mood.onAccent : colors.textPrimary,
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
