import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared/shared.dart';

import '../../l10n/app_localizations.dart';
import '../decor/decor_painter.dart';
import '../icons/app_icon.dart';
import '../theme/app_text.dart';
import '../theme/app_theme.dart';
import '../theme/mood_colors.dart';
import '../tokens/tokens.g.dart';
import 'day_cell.dart';
import 'tap_target.dart';

/// Карточка месяца (00-spec §6.3, макет `7:7`): фон `soft`, скругление 28,
/// тень card, декор первым слоем; полоса 60 с названием месяца ▾, годом и
/// стрелками ‹ ›; белая панель с днями недели (сб/вс — `accent-strong`),
/// сеткой 4–6 недель, разделителем и футером «В среднем … / день» /
/// «Итог за месяц …».
///
/// Ширина — сколько даст родитель (экран − 24), высота — по содержимому.
/// Цвета — настроения [mood] (на экране: сезон показываемого месяца или
/// праздник), а не всего приложения.
class MonthCard extends StatelessWidget {
  const MonthCard({
    super.key,
    required this.month,
    required this.today,
    required this.dayTotals,
    required this.mood,
    this.holidayMarks = const {},
    this.selectedDay,
    this.onMonthTap,
    this.onPrevious,
    this.onNext,
    this.onDayTap,
    this.decorPhase = 0,
  });

  final YearMonth month;
  final LocalDate today;

  /// Сумма трат по дням месяца (число → сумма); нет ключа — 0.
  final Map<int, Money> dayTotals;
  final Mood mood;

  /// Эмодзи праздника в углу ячейки (число → эмодзи).
  final Map<int, String> holidayMarks;
  final int? selectedDay;
  final VoidCallback? onMonthTap;
  final VoidCallback? onPrevious;

  /// `null` — стрелка › неактивна (следующий месяц будущий).
  final VoidCallback? onNext;
  final ValueChanged<int>? onDayTap;

  /// Фаза анимации декора (этап 13).
  final double decorPhase;

  static const double _radius = RadiusTokens.xl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final moodColors = MoodColors.forMood(mood, theme.brightness);
    // Своё настроение для всего внутри карточки (ячейки, рябь).
    final cardTheme = theme.copyWith(
      splashColor: moodColors.accent.withValues(alpha: 0.12),
      highlightColor: moodColors.accent.withValues(alpha: 0.08),
      extensions: [
        for (final e in theme.extensions.values)
          if (e is! MoodColors) e,
        moodColors,
      ],
    );
    return Theme(
      data: cardTheme,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: moodColors.soft,
          borderRadius: BorderRadius.circular(_radius),
          boxShadow: ShadowTokens.card,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(_radius),
          child: Stack(
            children: [
              Positioned.fill(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: DecorPainter(
                      mood: mood,
                      brightness: theme.brightness,
                      phase: decorPhase,
                      cornerRadius: _radius,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  12,
                  0,
                  12 - _Header.overhang,
                  12,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Header(
                      month: month,
                      onMonthTap: onMonthTap,
                      onPrevious: onPrevious,
                      onNext: onNext,
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: _Header.overhang),
                      child: _Panel(card: this),
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

class _Header extends StatelessWidget {
  const _Header({
    required this.month,
    required this.onMonthTap,
    required this.onPrevious,
    required this.onNext,
  });

  final YearMonth month;
  final VoidCallback? onMonthTap;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  static const double overhang = 9;

  static const double _arrowsWidth = 79;

  static const double _arrowMargin = 3;

  @override
  Widget build(BuildContext context) {
    final mood = context.mood;
    final l10n = AppLocalizations.of(context);
    final name = DateFormat.LLLL('ru')
        .format(DateTime(month.year, month.month));
    final title = TextStyleTokens.displayMonth.uppercase
        ? name.toUpperCase()
        : name;
    final monthLabel =
        '${name[0].toUpperCase()}${name.substring(1)} ${month.year}';

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 60),
      child: Padding(
        // Справа 2 по Figma — его даёт поле правой стрелки.
        padding: const EdgeInsets.only(left: 8),
        child: Stack(
          alignment: AlignmentDirectional.centerStart,
          children: [
            Positioned(
              right: kMinTapTarget,
              child: _NavButton(
                icon: AppIcons.chevronLeft,
                label: l10n.a11yPrevMonth,
                onTap: onPrevious,
                margin: const EdgeInsets.only(
                  left: kMinTapTarget - _NavButton.size - _arrowMargin,
                  right: _arrowMargin,
                ),
              ),
            ),
            Positioned(
              right: 0,
              child: _NavButton(
                icon: AppIcons.chevronRight,
                label: l10n.a11yNextMonth,
                onTap: onNext,
                margin: const EdgeInsets.only(
                  left: _arrowMargin,
                  right: kMinTapTarget - _NavButton.size - _arrowMargin,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: _arrowsWidth + overhang),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Semantics(
                  button: onMonthTap != null,
                  label: l10n.a11yChooseMonth(monthLabel),
                  excludeSemantics: true,
                  onTap: onMonthTap,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onMonthTap,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 48),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Название — одно слово: при крупном шрифте
                              // на узком экране уменьшается, а не рвётся.
                              Flexible(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    title,
                                    maxLines: 1,
                                    style: AppText.displayMonth.copyWith(
                                      color: mood.onSoft,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              AppIcon(
                                AppIcons.chevronDown,
                                size: 18,
                                color: mood.onSoft,
                              ),
                            ],
                          ),
                          Text(
                            '${month.year}',
                            style: AppText.caption.copyWith(color: mood.onSoft),
                          ),
                        ],
                      ),
                    ),
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

/// Круглая кнопка 34 со стрелкой. Область нажатия — кружок с полями
/// [margin] (48 × 48): кружки стоят с зазором 6, как в Figma, а области
/// заходят на поле карточки справа и на место под названием слева.
/// Неактивная — стрелка `text/disabled`.
class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.icon,
    required this.label,
    required this.margin,
    this.onTap,
  });

  final AppIcons icon;
  final String label;
  final EdgeInsets margin;
  final VoidCallback? onTap;

  static const double size = 34;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final mood = context.mood;
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
          height: kMinTapTarget,
          padding: margin,
          alignment: Alignment.center,
          child: Material(
            color: colors.bgSurface,
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
                    color: enabled ? mood.onSoft : colors.textDisabled,
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

class _Panel extends StatelessWidget {
  const _Panel({required this.card});

  final MonthCard card;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final mood = context.mood;
    final l10n = AppLocalizations.of(context);
    final month = card.month;
    final weeks = monthGrid(month);
    final scaler = MediaQuery.textScalerOf(context);
    final cellHeight = DayCell.heightFor(scaler);

    // Дни недели: с понедельника, «пн»…«вс» из intl.
    final monday = DateTime(2024, 1, 1); // понедельник
    final weekdays = [
      for (var i = 0; i < 7; i++)
        DateFormat.E('ru').format(monday.add(Duration(days: i))),
    ];

    final monthTotal = Money.sum(card.dayTotals.values);
    final average = averagePerDay(
      monthTotal: monthTotal,
      month: month,
      today: card.today,
    );
    final dateFormat = DateFormat('d MMMM', 'ru');

    Widget cell(LocalDate? date) {
      if (date == null) {
        return const DayCell(type: DayCellType.empty);
      }
      final sum = card.dayTotals[date.day] ?? Money.zero;
      final kind = dayKind(date, card.today);
      final type = DayCellType.of(kind, heatLevel(sum));
      final selected = card.selectedDay == date.day;
      final dateText = dateFormat.format(
        DateTime(date.year, date.month, date.day),
      );
      final parts = <String>[
        if (kind == DayKind.future)
          l10n.a11yDayFuture(dateText)
        else if (sum.kopecks > 0)
          l10n.a11yDaySpent(dateText, sum.roundedRubles)
        else
          l10n.a11yDayNoSpending(dateText),
        if (kind == DayKind.today) l10n.a11yDayToday,
        if (selected) l10n.a11yDaySelected,
      ];
      return DayCell(
        type: type,
        day: date.day,
        amount: kind == DayKind.future
            ? null
            : sum.kopecks > 0
            ? sum.formatCell()
            : '—',
        holidayEmoji: card.holidayMarks[date.day],
        selected: selected,
        semanticLabel: parts.join(', '),
        onTap: card.onDayTap == null ? null : () => card.onDayTap!(date.day),
      );
    }

    // Ячейки стоят с зазором 4; у каждой — поля по 2, и они тоже ловят
    // нажатие: область нажатия = ячейка + половина зазора с каждой стороны.
    Widget week(List<LocalDate?> days) => Row(
      children: [
        for (final date in days)
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              excludeFromSemantics: true,
              onTap: date == null || card.onDayTap == null
                  ? null
                  : () => card.onDayTap!(date.day),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: SizedBox(height: cellHeight, child: cell(date)),
              ),
            ),
          ),
      ],
    );

    return Container(
      decoration: BoxDecoration(
        color: colors.bgSurface,
        borderRadius: BorderRadius.circular(RadiusTokens.lg),
      ),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Row(
              children: [
                for (final (i, name) in weekdays.indexed) ...[
                  if (i > 0) const SizedBox(width: 4),
                  Expanded(
                    child: ExcludeSemantics(
                      child: Text(
                        name,
                        textAlign: TextAlign.center,
                        style: AppText.labelS.copyWith(
                          color: i >= 5
                              ? mood.accentStrong
                              : colors.textTertiary,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          // 8 по Figma минус 2 — поле ячейки.
          const SizedBox(height: 6),
          for (final days in weeks) week(days),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Container(height: 1, color: colors.borderDefault),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: _Footer(
              average: average == null
                  ? '—'
                  : l10n.monthAveragePerDay(average.formatTotal()),
              total: monthTotal.formatTotal(),
            ),
          ),
        ],
      ),
    );
  }
}

/// Футер карточки: «В среднем … / день» слева и «Итог за месяц …» справа.
/// Если рядом не помещаются (узкий экран, крупный шрифт) — итог встаёт под
/// средним, у правого края; слова переносятся целиком, сумма итога при
/// нехватке места уменьшается, но не обрезается.
class _Footer extends StatelessWidget {
  const _Footer({required this.average, required this.total});

  final String average;
  final String total;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final mood = context.mood;
    final l10n = AppLocalizations.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final captionStyle = AppText.caption.copyWith(color: colors.textTertiary);
    final averageStyle = AppText.labelM.copyWith(color: colors.textSecondary);
    final totalStyle = AppText.displayS.copyWith(color: mood.accentStrong);

    double width(String text, TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: Directionality.of(context),
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final w = painter.width;
      painter.dispose();
      return w;
    }

    final left = MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.monthAverage, style: captionStyle),
          const SizedBox(height: 2),
          Text(average, style: averageStyle),
        ],
      ),
    );
    final right = MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.monthTotal, textAlign: TextAlign.end, style: captionStyle),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(total, maxLines: 1, style: totalStyle),
          ),
        ],
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final leftWidth = [
          width(l10n.monthAverage, captionStyle),
          width(average, averageStyle),
        ].reduce((a, b) => a > b ? a : b);
        final rightWidth = [
          width(l10n.monthTotal, captionStyle),
          width(total, totalStyle),
        ].reduce((a, b) => a > b ? a : b);
        if (leftWidth + 8 + rightWidth <= constraints.maxWidth) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: left),
              const SizedBox(width: 8),
              right,
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            left,
            const SizedBox(height: 8),
            Align(alignment: Alignment.centerRight, child: right),
          ],
        );
      },
    );
  }
}
