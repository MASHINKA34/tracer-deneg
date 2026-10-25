import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/components/button.dart';
import '../../ui/components/fitting_text.dart';
import '../../ui/components/sheet.dart';
import '../../ui/components/tap_target.dart';
import '../../ui/theme/app_text.dart';
import '../../ui/theme/app_theme.dart';
import '../../ui/tokens/tokens.g.dart';

final _log = Logger('holidays');

const int birthdayLeapYear = 2000;

const int birthdayMonthColumns = 3;

const int birthdayDayMaxColumns = 7;

const double birthdayCellInset = 2;

sealed class BirthdayChoice {
  const BirthdayChoice();
}

final class BirthdayPicked extends BirthdayChoice {
  const BirthdayPicked(this.birthday);

  final MonthDay birthday;
}

final class BirthdayCleared extends BirthdayChoice {
  const BirthdayCleared();
}

String birthdayText(MonthDay birthday) => DateFormat(
  'd MMMM',
  'ru',
).format(DateTime(birthdayLeapYear, birthday.month, birthday.day));

String birthdayMonthName(int month) {
  final name = DateFormat.LLLL('ru').format(DateTime(birthdayLeapYear, month));
  return name.isEmpty ? name : '${name[0].toUpperCase()}${name.substring(1)}';
}

int birthdayDaysIn(int? month) =>
    month == null ? 31 : daysInMonth(birthdayLeapYear, month);

Future<BirthdayChoice?> showBirthdaySheet(
  BuildContext context, {
  required MonthDay? initial,
}) async {
  final sw = Stopwatch()..start();
  final root = Navigator.of(context, rootNavigator: true);
  _log.fine(
    'birthday sheet opened, date ${initial == null ? 'not set' : 'set'}',
  );
  final choice = await showAppSheet<BirthdayChoice>(
    root.context,
    builder: (context) => [BirthdaySheet(initial: initial)],
  );
  switch (choice) {
    case null:
      _log.fine(
        'birthday sheet closed without a choice after '
        '${sw.elapsedMilliseconds}ms: back gesture, tap outside or swipe down',
      );
    case BirthdayPicked():
      _log.fine('birthday sheet done after ${sw.elapsedMilliseconds}ms');
    case BirthdayCleared():
      _log.fine(
        'birthday sheet clear tapped after ${sw.elapsedMilliseconds}ms',
      );
  }
  return choice;
}

class BirthdaySheet extends StatefulWidget {
  const BirthdaySheet({super.key, required this.initial});

  final MonthDay? initial;

  @override
  State<BirthdaySheet> createState() => _BirthdaySheetState();
}

class _BirthdaySheetState extends State<BirthdaySheet> {
  late int? _month = widget.initial?.month;
  late int? _day = widget.initial?.day;

  void _selectMonth(int month) {
    if (month == _month) {
      _log.fine('birthday sheet month tapped again, already selected');
      return;
    }
    final days = birthdayDaysIn(month);
    final day = _day;
    setState(() {
      _month = month;
      if (day != null && day > days) _day = days;
    });
    _log.fine('birthday sheet month selected');
  }

  void _selectDay(int day) {
    if (day == _day) {
      _log.fine('birthday sheet day tapped again, already selected');
      return;
    }
    setState(() => _day = day);
    _log.fine('birthday sheet day selected');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final month = _month;
    final day = _day;
    return Flexible(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: FittingText(
                l10n.holidaysBirthdayTitle,
                style: AppText.titleM.copyWith(color: colors.textPrimary),
              ),
            ),
            const SizedBox(height: 16),
            _GridLabel(l10n.birthdaySheetMonth),
            const SizedBox(height: 8 - birthdayCellInset),
            _Grid(
              count: 12,
              columns: (_) => birthdayMonthColumns,
              selected: month,
              label: birthdayMonthName,
              onTap: _selectMonth,
            ),
            const SizedBox(height: 16 - birthdayCellInset),
            _GridLabel(l10n.birthdaySheetDay),
            const SizedBox(height: 8 - birthdayCellInset),
            _Grid(
              count: birthdayDaysIn(month),
              columns: (width) => math.max(
                1,
                math.min(
                  birthdayDayMaxColumns,
                  (width / kMinTapTarget).floor(),
                ),
              ),
              selected: day,
              label: (value) => '$value',
              onTap: _selectDay,
            ),
            const SizedBox(height: 16 - birthdayCellInset),
            AppButton(
              label: l10n.birthdaySheetDone,
              expand: true,
              onPressed: month != null && day != null
                  ? () =>
                        Navigator.of(context)
                            .pop(BirthdayPicked(MonthDay(month, day)))
                  : null,
            ),
            if (widget.initial != null) ...[
              const SizedBox(height: 8),
              AppButton(
                label: l10n.birthdaySheetClear,
                type: AppButtonType.text,
                destructive: true,
                expand: true,
                onPressed: () =>
                    Navigator.of(context).pop(const BirthdayCleared()),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _GridLabel extends StatelessWidget {
  const _GridLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => FittingText(
    text,
    style: AppText.labelM.copyWith(color: context.colors.textSecondary),
  );
}

class _Grid extends StatelessWidget {
  const _Grid({
    required this.count,
    required this.columns,
    required this.selected,
    required this.label,
    required this.onTap,
  });

  final int count;
  final int Function(double width) columns;
  final int? selected;
  final String Function(int value) label;
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
        final perRow = columns(constraints.maxWidth);
        final width = constraints.maxWidth / perRow;
        final rows = (count / perRow).ceil();
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var row = 0; row < rows; row++)
              Row(
                children: [
                  for (var column = 0; column < perRow; column++)
                    SizedBox(
                      width: width,
                      height: height,
                      child: row * perRow + column < count
                          ? _Cell(
                              text: label(row * perRow + column + 1),
                              selected: row * perRow + column + 1 == selected,
                              onTap: () => onTap(row * perRow + column + 1),
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

class _Cell extends StatelessWidget {
  const _Cell({
    required this.text,
    required this.selected,
    required this.onTap,
  });

  final String text;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final mood = context.mood;
    final radius = BorderRadius.circular(RadiusTokens.sm);
    return Semantics(
      button: true,
      selected: selected,
      label: [text, if (selected) l10n.a11yDaySelected].join(', '),
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(birthdayCellInset),
          child: Material(
            color: selected ? mood.accent : colors.bgSurface2,
            borderRadius: radius,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    text,
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
      ),
    );
  }
}
