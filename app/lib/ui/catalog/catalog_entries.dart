import 'package:flutter/material.dart';
import 'package:shared/shared.dart';

import '../components/avatar.dart';
import '../components/bottom_nav.dart';
import '../components/button.dart';
import '../components/category_badge.dart';
import '../components/category_tile.dart';
import '../components/checkbox.dart';
import '../components/chip.dart';
import '../components/day_cell.dart';
import '../components/dialog.dart';
import '../components/expense_row.dart';
import '../components/fitting_text.dart';
import '../components/fab.dart';
import '../components/holiday_banner.dart';
import '../components/keypad_key.dart';
import '../components/list_row.dart';
import '../components/logo.dart';
import '../components/month_card.dart';
import '../components/month_tab.dart';
import '../components/radio.dart';
import '../components/segmented.dart';
import '../components/sheet.dart';
import '../components/snackbar.dart';
import '../components/stat_row.dart';
import '../components/sync_status.dart';
import '../components/text_field.dart';
import '../components/toggle.dart';
import '../icons/app_icon.dart';
import '../theme/app_text.dart';
import '../theme/app_theme.dart';
import '../tokens/tokens.g.dart';
import 'demo_months.dart';

/// Подложка раздела каталога — как у набора в Figma.
enum CatalogBackground { app, surface, surface2 }

/// Раздел каталога компонентов: один компонент Figma со всеми вариантами.
/// Те же разделы снимают эталонные скриншоты (`test/ui/golden`), поэтому
/// каталог и эталоны не расходятся. Тексты-примеры — из макетов (только
/// для debug-сборки, в ARB не выносятся — решение этапа 03).
final class CatalogEntry {
  const CatalogEntry({
    required this.id,
    required this.title,
    required this.figmaNode,
    required this.builder,
    this.background = CatalogBackground.app,
  });

  /// Имя файла эталона: `button` → `button_light.png`.
  final String id;
  final String title;

  /// Узел в Figma для сверки.
  final String figmaNode;
  final WidgetBuilder builder;
  final CatalogBackground background;

  Color backgroundColor(BuildContext context) => switch (background) {
    CatalogBackground.app => context.colors.bgApp,
    CatalogBackground.surface => context.colors.bgSurface,
    CatalogBackground.surface2 => context.colors.bgSurface2,
  };
}

void _noop() {}

Widget _wrap(List<Widget> children, {double spacing = 16}) => Wrap(
  spacing: spacing,
  runSpacing: spacing,
  crossAxisAlignment: WrapCrossAlignment.center,
  children: children,
);

Widget _column(List<Widget> children, {double spacing = 16}) => Column(
  crossAxisAlignment: CrossAxisAlignment.stretch,
  mainAxisSize: MainAxisSize.min,
  children: [
    for (final (i, c) in children.indexed) ...[
      if (i > 0) SizedBox(height: spacing),
      c,
    ],
  ],
);

/// Все разделы каталога по порядку страницы «Компоненты» в Figma.
final List<CatalogEntry> catalogEntries = [
  CatalogEntry(
    id: 'colors',
    title: 'Цвета темы и настроения',
    figmaNode: '2:3',
    builder: (context) => const _ColorsSample(),
  ),
  CatalogEntry(
    id: 'text_styles',
    title: 'Текстовые стили (19)',
    figmaNode: '2:3',
    builder: (context) => const _TextStylesSample(),
  ),
  CatalogEntry(
    id: 'icons',
    title: 'Иконки (35)',
    figmaNode: '3:2',
    builder: (context) => _wrap([
      for (final icon in AppIcons.values)
        SizedBox(
          width: 64,
          child: Column(
            children: [
              AppIcon(icon, color: context.colors.textPrimary),
              const SizedBox(height: 4),
              FittingText(
                icon.figmaName,
                textAlign: TextAlign.center,
                style: AppText.micro.copyWith(
                  color: context.colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
    ], spacing: 8),
  ),
  CatalogEntry(
    id: 'avatar',
    title: 'Avatar',
    figmaNode: '3:185',
    builder: (context) => _wrap([
      for (final size in AvatarSize.values) AppAvatar(letter: 'А', size: size),
    ]),
  ),
  CatalogEntry(
    id: 'button',
    title: 'Button',
    figmaNode: '3:218',
    builder: (context) => const _ButtonsSample(),
  ),
  CatalogEntry(
    id: 'text_field',
    title: 'TextField',
    figmaNode: '3:252',
    builder: (context) => const _TextFieldsSample(),
  ),
  CatalogEntry(
    id: 'chip',
    title: 'Chip',
    figmaNode: '3:259',
    builder: (context) => _wrap([
      AppChip(label: 'Сегодня, 19 окт', emoji: '📅', onTap: _noop),
      AppChip(
        label: 'Сегодня, 19 окт',
        emoji: '📅',
        selected: true,
        onTap: _noop,
      ),
      AppChip(label: 'Этот месяц', onTap: _noop),
    ], spacing: 8),
  ),
  CatalogEntry(
    id: 'toggle',
    title: 'Toggle',
    figmaNode: '26:3636',
    builder: (context) => _wrap([
      AppToggle(value: true, onChanged: (_) {}),
      AppToggle(value: false, onChanged: (_) {}),
      const AppToggle(value: true, onChanged: null),
    ]),
  ),
  CatalogEntry(
    id: 'segmented',
    title: 'Segmented',
    figmaNode: '41:4094',
    builder: (context) => _column([
      AppSegmented<int>(
        options: const [SegmentOption(0, 'Месяц'), SegmentOption(1, 'Год')],
        selected: 0,
        onChanged: (_) {},
      ),
      AppSegmented<int>(
        options: const [SegmentOption(0, 'Месяц'), SegmentOption(1, 'Год')],
        selected: 1,
        onChanged: (_) {},
      ),
    ]),
  ),
  CatalogEntry(
    id: 'checkbox_radio',
    title: 'Checkbox, Radio',
    figmaNode: '41:4099',
    builder: (context) => _wrap([
      AppCheckbox(value: true, onChanged: (_) {}),
      AppCheckbox(value: false, onChanged: (_) {}),
      const AppRadio(selected: true, onTap: _noop),
      const AppRadio(selected: false, onTap: _noop),
    ], spacing: 0),
  ),
  CatalogEntry(
    id: 'category_badge',
    title: 'CategoryBadge',
    figmaNode: '4:33',
    builder: (context) => _wrap(const [
      CategoryBadge(emoji: '🛒', color: CategoryColor.green),
      CategoryBadge(emoji: '☕', color: CategoryColor.orange),
      CategoryBadge(emoji: '🚇', color: CategoryColor.yellow),
      CategoryBadge(emoji: '🏠', color: CategoryColor.blue),
      CategoryBadge(emoji: '💊', color: CategoryColor.red),
      CategoryBadge(emoji: '🏋️', color: CategoryColor.indigo),
      CategoryBadge(emoji: '🎮', color: CategoryColor.pink),
      CategoryBadge(emoji: '👕', color: CategoryColor.purple),
      CategoryBadge(emoji: '📱', color: CategoryColor.teal),
      CategoryBadge(emoji: '🎁', color: CategoryColor.rose),
      CategoryBadge(emoji: '📦', color: null),
    ], spacing: 8),
  ),
  CatalogEntry(
    id: 'category_tile',
    title: 'CategoryTile',
    figmaNode: '4:43',
    builder: (context) => _wrap([
      const CategoryTile(
        emoji: '🛒',
        name: 'Продукты',
        color: CategoryColor.green,
        onTap: _noop,
      ),
      const CategoryTile(
        emoji: '🛒',
        name: 'Продукты',
        color: CategoryColor.green,
        selected: true,
        onTap: _noop,
      ),
      const CategoryTile(
        emoji: '🎮',
        name: 'Развлечения',
        color: CategoryColor.pink,
        onTap: _noop,
      ),
      const CategoryTile(
        emoji: '📦',
        name: 'Другое',
        color: null,
        onTap: _noop,
      ),
    ]),
  ),
  CatalogEntry(
    id: 'expense_row',
    title: 'ExpenseRow',
    figmaNode: '4:44',
    background: CatalogBackground.surface,
    builder: (context) => _column(spacing: 0, const [
      ExpenseRow(
        emoji: '🛒',
        color: CategoryColor.green,
        title: 'Продукты',
        subtitle: 'Пятёрочка · 14:20',
        amount: '640 ₽',
        onTap: _noop,
      ),
      ExpenseRow(
        emoji: '☕',
        color: CategoryColor.orange,
        title: 'Кафе',
        subtitle: 'Обед с коллегами · 13:30',
        amount: '1 280 ₽',
        author: ExpenseAuthor(
          letter: 'Д',
          color: CategoryColor.green,
          name: 'Дима',
        ),
        onTap: _noop,
      ),
      ExpenseRow(
        emoji: '📦',
        color: null,
        title: 'Другое',
        subtitle:
            'Очень длинный комментарий, который не помещается в одну строку',
        amount: '149,90 ₽',
        onTap: _noop,
      ),
    ]),
  ),
  CatalogEntry(
    id: 'list_row',
    title: 'ListRow',
    figmaNode: '4:53',
    background: CatalogBackground.surface,
    builder: (context) => _column(spacing: 0, const [
      ListRow(
        icon: AppIcons.tag,
        title: 'Категории',
        value: '12',
        onTap: _noop,
      ),
      ListRow(
        icon: AppIcons.moon,
        title: 'Тема',
        value: 'Как в системе',
        onTap: _noop,
      ),
      ListRow(
        icon: AppIcons.logOut,
        title: 'Выйти',
        chevron: false,
        onTap: _noop,
      ),
    ]),
  ),
  CatalogEntry(
    id: 'stat_row',
    title: 'StatRow',
    figmaNode: '4:62',
    background: CatalogBackground.surface,
    builder: (context) => _column(spacing: 0, const [
      StatRow(
        emoji: '🛒',
        color: CategoryColor.green,
        name: 'Продукты',
        share: '34% · 18 покупок',
        amount: '6 240 ₽',
        fraction: 0.34,
        onTap: _noop,
      ),
      StatRow(
        emoji: '☕',
        color: CategoryColor.orange,
        name: 'Кафе',
        share: '21% · 9 покупок',
        amount: '3 850 ₽',
        fraction: 0.62,
        onTap: _noop,
      ),
    ]),
  ),
  CatalogEntry(
    id: 'day_cell',
    title: 'DayCell',
    figmaNode: '4:32',
    background: CatalogBackground.surface,
    builder: (context) => const _DayCellsSample(),
  ),
  CatalogEntry(
    id: 'keypad_key',
    title: 'KeypadKey',
    figmaNode: '5:161',
    background: CatalogBackground.surface2,
    builder: (context) => Row(
      children: [
        Expanded(child: KeypadKey.symbol('7', onTap: _noop)),
        const SizedBox(width: 16),
        Expanded(child: KeypadKey.symbol(',', onTap: _noop)),
        const SizedBox(width: 16),
        const Expanded(child: KeypadKey.backspace(onTap: _noop)),
      ],
    ),
  ),
  CatalogEntry(
    id: 'month_tab',
    title: 'MonthTab',
    figmaNode: '5:177',
    background: CatalogBackground.surface,
    builder: (context) => _wrap(const [
      MonthTab(
        letter: 'О',
        state: MonthTabState.normal,
        fraction: 50 / 72,
        onTap: _noop,
      ),
      MonthTab(
        letter: 'О',
        state: MonthTabState.selected,
        fraction: 50 / 72,
        onTap: _noop,
      ),
      MonthTab(letter: 'О', state: MonthTabState.future),
    ], spacing: 24),
  ),
  CatalogEntry(
    id: 'fab',
    title: 'Fab',
    figmaNode: '5:27',
    builder: (context) => _wrap(const [
      AppFab(onPressed: _noop),
      AppFab(onPressed: _noop, stickerEmoji: '🎃'),
    ], spacing: 24),
  ),
  CatalogEntry(
    id: 'bottom_nav',
    title: 'BottomNav',
    figmaNode: '5:154',
    // Сверху место под «+»: он выступает над меню на 26.
    builder: (context) => _column(spacing: 48, [
      const SizedBox(height: 0),
      for (final tab in AppNavTab.values)
        AppBottomNav(
          active: tab,
          onTabSelected: (_) {},
          onAdd: _noop,
          fabSticker: tab == AppNavTab.profile ? '🎃' : null,
        ),
    ]),
  ),
  CatalogEntry(
    id: 'holiday_banner',
    title: 'HolidayBanner',
    figmaNode: '26:3600',
    builder: (context) => _column([
      const HolidayBanner.countdown(
        emoji: '🎃',
        title: 'До Хеллоуина 3 дня',
        subtitle: 'Запасайся конфетами 🍬',
        onClose: _noop,
      ),
      const HolidayBanner.greeting(
        emoji: '🎃',
        title: 'С Хеллоуином!',
        subtitle: 'Сладость или гадость? 🍬',
        onClose: _noop,
      ),
      const HolidayBanner.member(
        avatarLetter: 'Д',
        avatarColor: CategoryColor.green,
        title: '🎂 Дима — день рождения через 3 дня',
        subtitle: '2 декабря · бюджет «Семья»',
        onClose: _noop,
      ),
    ]),
  ),
  CatalogEntry(
    id: 'sync_status',
    title: 'SyncStatus',
    figmaNode: '41:4127',
    builder: (context) => _wrap(const [
      SyncStatus(state: SyncState.done),
      SyncStatus(state: SyncState.waiting, pending: 3),
      SyncStatus(state: SyncState.syncing),
      SyncStatus(state: SyncState.error),
    ], spacing: 8),
  ),
  CatalogEntry(
    id: 'snackbar',
    title: 'Snackbar',
    figmaNode: '41:4128',
    builder: (context) => _column(const [
      AppSnackbar(
        text: 'Трата удалена',
        actionLabel: 'Отменить',
        onAction: _noop,
      ),
      AppSnackbar(text: 'Нет связи с сервером. Траты сохранены на телефоне'),
    ]),
  ),
  CatalogEntry(
    id: 'logo',
    title: 'Logo',
    figmaNode: '5:178',
    builder: (context) => _wrap(const [AppLogo(), AppLogo(size: 40)]),
  ),
  CatalogEntry(
    id: 'sheet',
    title: 'Шторка',
    figmaNode: '9:439',
    builder: (context) => const _SheetSample(),
  ),
  CatalogEntry(
    id: 'dialog',
    title: 'Диалог',
    figmaNode: '42:4321',
    builder: (context) => AppDialog(
      icon: AppIcons.cloudOff,
      title: '3 траты ещё не на сервере',
      message:
          'Сейчас нет связи. Если выйти, эти траты пропадут с телефона. '
          'Подожди сеть — мы отправим их сами.',
      primary: const AppDialogAction('Синхронизировать', _noop),
      secondary: const AppDialogAction(
        'Выйти и потерять',
        _noop,
        destructive: true,
      ),
    ),
  ),
  CatalogEntry(
    id: 'month_card',
    title: 'MonthCard (настроение каталога)',
    figmaNode: '7:7',
    builder: (context) {
      final demo = demoMonthFor(context.mood.mood);
      return MonthCard(
        month: demo.month,
        today: demo.today,
        dayTotals: demo.dayTotals,
        mood: demo.mood,
        holidayMarks: demo.marks,
        onMonthTap: _noop,
        onPrevious: _noop,
        onDayTap: (_) {},
      );
    },
  ),
];

class _ButtonsSample extends StatefulWidget {
  const _ButtonsSample();

  @override
  State<_ButtonsSample> createState() => _ButtonsSampleState();
}

class _ButtonsSampleState extends State<_ButtonsSample> {
  final List<WidgetStatesController> _pressed = [];

  WidgetStatesController _pressedController() {
    final c = WidgetStatesController({WidgetState.pressed});
    _pressed.add(c);
    return c;
  }

  @override
  void dispose() {
    for (final c in _pressed) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    Widget caption(String text) =>
        Text(text, style: AppText.caption.copyWith(color: colors.textTertiary));
    return _column([
      for (final type in AppButtonType.values)
        _wrap([
          for (final size in AppButtonSize.values)
            AppButton(
              label: 'Кнопка',
              onPressed: _noop,
              type: type,
              size: size,
            ),
          AppButton(
            label: 'Кнопка',
            onPressed: _noop,
            type: type,
            size: AppButtonSize.m,
            icon: AppIcons.plus,
          ),
        ], spacing: 12),
      caption('Text · destructive (диалог 42:4321)'),
      const AppButton(
        label: 'Выйти и потерять',
        onPressed: _noop,
        type: AppButtonType.text,
        destructive: true,
      ),
      caption('Нажата (рябь + затемнение)'),
      _wrap([
        for (final type in AppButtonType.values)
          AppButton(
            label: 'Кнопка',
            onPressed: _noop,
            type: type,
            size: AppButtonSize.m,
            statesController: _pressedController(),
          ),
      ], spacing: 12),
      caption('Недоступна'),
      _wrap([
        for (final type in AppButtonType.values)
          AppButton(
            label: 'Кнопка',
            onPressed: null,
            type: type,
            size: AppButtonSize.m,
          ),
      ], spacing: 12),
      caption('На всю ширину, с иконкой'),
      const AppButton(
        label: 'Добавить трату в этот день',
        onPressed: _noop,
        type: AppButtonType.soft,
        icon: AppIcons.plus,
        expand: true,
      ),
    ], spacing: 12);
  }
}

class _TextFieldsSample extends StatefulWidget {
  const _TextFieldsSample();

  @override
  State<_TextFieldsSample> createState() => _TextFieldsSampleState();
}

class _TextFieldsSampleState extends State<_TextFieldsSample> {
  final _focused = TextEditingController(text: 'Придумай логин');
  final _error = TextEditingController(text: 'Придумай логин');
  final _password = TextEditingController(text: 'qwerty123');

  @override
  void dispose() {
    _focused.dispose();
    _error.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _column([
    const AppTextField(
      key: ValueKey('field-default'),
      label: 'Логин',
      placeholder: 'Придумай логин',
      icon: AppIcons.user,
    ),
    AppTextField(
      key: const ValueKey('field-focused'),
      label: 'Логин',
      controller: _focused,
      icon: AppIcons.user,
    ),
    AppTextField(
      key: const ValueKey('field-error'),
      label: 'Логин',
      controller: _error,
      icon: AppIcons.user,
      errorText: 'Только латиница и цифры',
    ),
    AppTextField(
      key: const ValueKey('field-password'),
      label: 'Пароль',
      controller: _password,
      icon: AppIcons.lock,
      password: true,
      helperText: 'Не короче 8 символов',
    ),
  ]);
}

class _DayCellsSample extends StatelessWidget {
  const _DayCellsSample();

  @override
  Widget build(BuildContext context) {
    final height = DayCell.heightFor(MediaQuery.textScalerOf(context));
    Widget cell(DayCell c) => SizedBox(width: 40, height: height, child: c);
    return _wrap(spacing: 12, [
      cell(const DayCell(type: DayCellType.empty)),
      cell(const DayCell(type: DayCellType.future, day: 12)),
      cell(const DayCell(type: DayCellType.zero, day: 12, amount: '—')),
      cell(const DayCell(type: DayCellType.low, day: 12, amount: '1 280')),
      cell(const DayCell(type: DayCellType.medium, day: 12, amount: '1 280')),
      cell(const DayCell(type: DayCellType.high, day: 12, amount: '1 280')),
      cell(const DayCell(type: DayCellType.today, day: 12, amount: '1 280')),
      cell(
        const DayCell(type: DayCellType.future, day: 31, holidayEmoji: '🎃'),
      ),
      cell(
        const DayCell(
          type: DayCellType.today,
          day: 31,
          amount: '12,4к',
          holidayEmoji: '🎃',
        ),
      ),
      cell(
        const DayCell(
          type: DayCellType.medium,
          day: 17,
          amount: '1 450',
          selected: true,
        ),
      ),
      cell(const DayCell(type: DayCellType.high, day: 28, amount: '1,3м')),
    ]);
  }
}

class _SheetSample extends StatelessWidget {
  const _SheetSample();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final mood = context.mood;
    return AppSheet(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FittingText(
                    'Пятница, 17 октября',
                    style: AppText.titleM.copyWith(color: colors.textPrimary),
                  ),
                  const SizedBox(height: 2),
                  FittingText(
                    '2 траты · больше среднего на 487 ₽',
                    style: AppText.caption.copyWith(color: colors.textTertiary),
                  ),
                ],
              ),
            ),
            Text(
              '1 450 ₽',
              style: AppText.displayS.copyWith(color: mood.accentStrong),
            ),
          ],
        ),
        Container(
          decoration: BoxDecoration(
            color: colors.bgSurface2,
            borderRadius: BorderRadius.circular(RadiusTokens.lg),
          ),
          clipBehavior: Clip.antiAlias,
          child: const Column(
            children: [
              ExpenseRow(
                emoji: '☕',
                color: CategoryColor.orange,
                title: 'Кафе',
                subtitle: 'Обед с коллегами · 13:30',
                amount: '890 ₽',
              ),
              ExpenseRow(
                emoji: '🛒',
                color: CategoryColor.green,
                title: 'Продукты',
                subtitle: 'ВкусВилл · 19:10',
                amount: '560 ₽',
              ),
            ],
          ),
        ),
        const AppButton(
          label: 'Добавить трату в этот день',
          onPressed: _noop,
          type: AppButtonType.soft,
          icon: AppIcons.plus,
          expand: true,
        ),
      ],
    );
  }
}

class _ColorsSample extends StatelessWidget {
  const _ColorsSample();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final mood = context.mood;
    Widget swatch(String name, Color color) => SizedBox(
      width: 76,
      child: Column(
        children: [
          Container(
            height: 32,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(RadiusTokens.xs),
              border: Border.all(color: colors.borderDefault),
            ),
          ),
          const SizedBox(height: 2),
          FittingText(
            name,
            textAlign: TextAlign.center,
            style: AppText.micro.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
    return _column([
      _wrap(spacing: 8, [
        swatch('accent', mood.accent),
        swatch('accent-strong', mood.accentStrong),
        swatch('on-accent', mood.onAccent),
        swatch('soft', mood.soft),
        swatch('on-soft', mood.onSoft),
        swatch('heat-1', mood.heat1),
        swatch('heat-2', mood.heat2),
        swatch('heat-3', mood.heat3),
        swatch('decor-1', mood.decor1),
        swatch('decor-2', mood.decor2),
        swatch('decor-3', mood.decor3),
        swatch('decor-4', mood.decor4),
      ]),
      _wrap(spacing: 8, [
        swatch('bg/app', colors.bgApp),
        swatch('bg/surface', colors.bgSurface),
        swatch('surface-2', colors.bgSurface2),
        swatch('surface-3', colors.bgSurface3),
        swatch('border', colors.borderDefault),
        swatch('border/strong', colors.borderStrong),
        swatch('text/primary', colors.textPrimary),
        swatch('secondary', colors.textSecondary),
        swatch('tertiary', colors.textTertiary),
        swatch('disabled', colors.textDisabled),
        swatch('success', colors.statusSuccess),
        swatch('danger', colors.statusDanger),
      ]),
      _wrap(spacing: 8, [
        for (final c in CategoryColor.values) ...[
          swatch(c.name, colors.categories[c]!.solid),
          swatch('${c.name}-soft', colors.categories[c]!.soft),
        ],
      ]),
    ]);
  }
}

class _TextStylesSample extends StatelessWidget {
  const _TextStylesSample();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final styles = <(String, TextStyle)>[
      ('Display/XL 18 300 ₽', AppText.displayXl),
      ('Display/L 18 300 ₽', AppText.displayL),
      ('Display/M Милиончик', AppText.displayM),
      ('Display/S 18 300 ₽', AppText.displayS),
      ('ОКТЯБРЬ · Display/Month', AppText.displayMonth),
      ('Title/L Профиль', AppText.titleL),
      ('Title/M Пятница, 17 октября', AppText.titleM),
      ('Title/S Бюджеты', AppText.titleS),
      ('Body/L Категории', AppText.bodyL),
      ('Body/M Сейчас нет связи', AppText.bodyM),
      ('Body/S Подсказка', AppText.bodyS),
      ('Label/L Кнопка', AppText.labelL),
      ('Label/M Продукты', AppText.labelM),
      ('Label/S Логин', AppText.labelS),
      ('Caption Пятёрочка · 14:20', AppText.caption),
      ('Micro Статистика', AppText.micro),
      ('Numeric/M 6 240 ₽', AppText.numericM),
      ('Cell/Day 12', AppText.cellDay),
      ('Cell/Amount 1 280', AppText.cellAmount),
    ];
    return _column(spacing: 6, [
      for (final (text, style) in styles)
        FittingText(text, style: style.copyWith(color: colors.textPrimary)),
    ]);
  }
}
