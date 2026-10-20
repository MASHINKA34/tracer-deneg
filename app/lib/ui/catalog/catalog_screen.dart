import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart' show Mood;

import '../components/button.dart';
import '../components/chip.dart';
import '../components/dialog.dart';
import '../components/segmented.dart';
import '../components/sheet.dart';
import '../components/snackbar.dart';
import '../icons/app_icon.dart';
import '../theme/app_text.dart';
import '../theme/app_theme.dart';
import 'catalog_entries.dart';

final _log = Logger('catalog');

/// Каталог компонентов — только в debug-сборке (долгий тап по логотипу на
/// заглушке). Переключатели темы, 15 настроений, масштаба шрифта и ширины;
/// все разделы [catalogEntries] в выбранных условиях. Главный инструмент
/// проверки этапа 03.
class CatalogScreen extends StatefulWidget {
  const CatalogScreen({super.key, this.initialBrightness, this.initialMood});

  final Brightness? initialBrightness;
  final Mood? initialMood;

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

/// Ширина превью: экран целиком или 320 / 360 / 412 dp.
const List<double?> _widths = [null, 320, 360, 412];
const List<double> _scales = [1, 1.3, 2];

class _CatalogScreenState extends State<CatalogScreen> {
  late Brightness _brightness;
  late Mood _mood;
  double _scale = 1;
  double? _width;

  @override
  void initState() {
    super.initState();
    _brightness = widget.initialBrightness ?? Brightness.light;
    _mood = widget.initialMood ?? Mood.autumn;
    _log.info(
      'catalog opened theme=${_brightness.name} mood=${_mood.name} '
      'entries=${catalogEntries.length}',
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.initialBrightness == null) {
      _brightness = Theme.of(context).brightness;
    }
  }

  void _set(String what, Object value, VoidCallback change) {
    setState(change);
    _log.fine('catalog $what → $value');
  }

  @override
  Widget build(BuildContext context) {
    final preview = AppTheme.build(_brightness, _mood);
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Controls(
              brightness: _brightness,
              mood: _mood,
              scale: _scale,
              width: _width,
              onBrightness: (b) => _set('theme', b.name, () => _brightness = b),
              onMood: (m) => _set('mood', m.name, () => _mood = m),
              onScale: (s) => _set('text scale', s, () => _scale = s),
              onWidth: (w) => _set('width', w ?? 'screen', () => _width = w),
            ),
            Expanded(
              child: AnimatedTheme(
                data: preview,
                duration: AppTheme.transition,
                child: Builder(
                  builder: (context) => ColoredBox(
                    color: context.colors.bgApp,
                    child: MediaQuery(
                      data: MediaQuery.of(context)
                          .copyWith(textScaler: TextScaler.linear(_scale)),
                      child: _Preview(width: _width),
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

class _Controls extends StatelessWidget {
  const _Controls({
    required this.brightness,
    required this.mood,
    required this.scale,
    required this.width,
    required this.onBrightness,
    required this.onMood,
    required this.onScale,
    required this.onWidth,
  });

  final Brightness brightness;
  final Mood mood;
  final double scale;
  final double? width;
  final ValueChanged<Brightness> onBrightness;
  final ValueChanged<Mood> onMood;
  final ValueChanged<double> onScale;
  final ValueChanged<double?> onWidth;

  static String _emoji(Mood mood) =>
      mood.holiday?.emoji ??
      switch (mood) {
        Mood.winter => '❄️',
        Mood.spring => '🌷',
        Mood.summer => '☀️',
        _ => '🍂',
      };

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // Пульт — без масштаба шрифта и всегда в своей теме.
    return MediaQuery.withNoTextScaling(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.bgSurface,
          border: Border(bottom: BorderSide(color: colors.borderDefault)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Каталог компонентов',
                      style: AppText.titleM.copyWith(color: colors.textPrimary),
                    ),
                  ),
                  Text(
                    'debug',
                    style: AppText.caption.copyWith(color: colors.textTertiary),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              AppSegmented<Brightness>(
                options: const [
                  SegmentOption(Brightness.light, 'Светлая'),
                  SegmentOption(Brightness.dark, 'Тёмная'),
                ],
                selected: brightness,
                onChanged: onBrightness,
              ),
              AppSegmented<double>(
                options: [
                  for (final s in _scales) SegmentOption(s, 'Шрифт ×$s'),
                ],
                selected: scale,
                onChanged: onScale,
              ),
              AppSegmented<double?>(
                options: [
                  for (final w in _widths)
                    SegmentOption(w, w == null ? 'Экран' : '${w.toInt()} dp'),
                ],
                selected: width,
                onChanged: onWidth,
              ),
              SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final m in Mood.values) ...[
                      AppChip(
                        label: m.name,
                        emoji: _emoji(m),
                        selected: m == mood,
                        onTap: () => onMood(m),
                      ),
                      const SizedBox(width: 6),
                    ],
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

class _Preview extends StatelessWidget {
  const _Preview({required this.width});

  final double? width;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final content = ListView(
      padding: const EdgeInsets.only(bottom: 48),
      children: [
        _Actions(),
        for (final entry in catalogEntries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: Text(
              '${entry.title} · ${entry.figmaNode}',
              style: AppText.labelS.copyWith(color: colors.textTertiary),
            ),
          ),
          Container(
            color: entry.backgroundColor(context),
            padding: const EdgeInsets.all(16),
            child: Builder(builder: entry.builder),
          ),
        ],
      ],
    );
    if (width == null) return content;
    return Center(
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.symmetric(
            vertical: BorderSide(color: colors.borderStrong),
          ),
        ),
        child: SizedBox(width: width, child: content),
      ),
    );
  }
}

/// Кнопки, которые открывают настоящие шторку, диалог и снекбар.
class _Actions extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          AppButton(
            label: 'Шторка',
            size: AppButtonSize.m,
            type: AppButtonType.soft,
            onPressed: () {
              _log.fine('catalog open sheet');
              showAppSheet<void>(
                context,
                builder: (context) => [
                  Text(
                    'Пятница, 17 октября',
                    style: AppText.titleM.copyWith(
                      color: context.colors.textPrimary,
                    ),
                  ),
                  AppButton(
                    label: 'Закрыть',
                    expand: true,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              );
            },
          ),
          AppButton(
            label: 'Диалог',
            size: AppButtonSize.m,
            type: AppButtonType.soft,
            onPressed: () {
              _log.fine('catalog open dialog');
              showAppDialog<void>(
                context,
                builder: (context) => AppDialog(
                  icon: AppIcons.cloudOff,
                  title: '3 траты ещё не на сервере',
                  message: 'Сейчас нет связи. Если выйти, эти траты пропадут с телефона.',
                  primary: AppDialogAction(
                    'Синхронизировать',
                    () => Navigator.of(context).pop(),
                  ),
                  secondary: AppDialogAction(
                    'Выйти и потерять',
                    () => Navigator.of(context).pop(),
                    destructive: true,
                  ),
                ),
              );
            },
          ),
          AppButton(
            label: 'Снекбар',
            size: AppButtonSize.m,
            type: AppButtonType.soft,
            onPressed: () {
              _log.fine('catalog show snackbar');
              showAppSnackbar(
                context,
                text: 'Трата 640 ₽ удалена',
                actionLabel: 'Отменить',
                onAction: () => _log.fine('catalog snackbar action'),
              );
            },
          ),
        ],
      ),
    );
  }
}
