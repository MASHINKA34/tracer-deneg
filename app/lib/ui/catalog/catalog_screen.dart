import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart' show LocalDate, Mood;

import '../../core/clock.dart';
import '../../data/api/api_error_text.dart';
import '../../data/api/api_exception.dart';
import '../../data/api/api_providers.dart';
import '../../data/sync/sync_engine.dart';
import '../../l10n/app_localizations.dart';
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
              const _TodayControls(),
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

class _TodayControls extends ConsumerWidget {
  const _TodayControls();

  static String _label(LocalDate today) {
    final pattern = today.year == DateTime.now().year ? 'd MMMM' : 'd MMMM y';
    final date = DateTime(today.year, today.month, today.day);
    return 'Сегодня = ${DateFormat(pattern, 'ru').format(date)}';
  }

  Future<void> _pick(BuildContext context, WidgetRef ref) async {
    final today = ref.read(clockProvider).today();
    final override = ref.read(todayOverrideProvider.notifier);
    _log.fine('catalog today picker opened initial=$today');
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(today.year, today.month, today.day),
      firstDate: DateTime(2000),
      lastDate: DateTime(2099, 12, 31),
    );
    if (picked == null) {
      _log.fine('catalog today picker cancelled, today stays $today');
      return;
    }
    final saved = await override.set(LocalDate.fromDateTime(picked));
    if (!saved && context.mounted) {
      showAppSnackbar(context, text: 'Не удалось сохранить дату');
    }
  }

  Future<void> _reset(BuildContext context, WidgetRef ref) async {
    _log.fine('catalog today reset tap');
    final saved = await ref.read(todayOverrideProvider.notifier).reset();
    if (!saved && context.mounted) {
      showAppSnackbar(context, text: 'Не удалось сбросить дату');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(clockProvider).today();
    final overridden = ref.watch(todayOverrideProvider) != null;
    return Row(
      children: [
        Expanded(
          child: AppButton(
            label: _label(today),
            size: AppButtonSize.m,
            type: AppButtonType.soft,
            expand: true,
            onPressed: () => _pick(context, ref),
          ),
        ),
        const SizedBox(width: 8),
        AppButton(
          label: 'Сбросить',
          size: AppButtonSize.m,
          type: AppButtonType.text,
          onPressed: overridden ? () => _reset(context, ref) : null,
        ),
      ],
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
          const _ApiHealthButton(),
          const _SyncCycleButton(),
        ],
      ),
    );
  }
}

class _ApiHealthButton extends ConsumerWidget {
  const _ApiHealthButton();

  Future<void> _check(BuildContext context, WidgetRef ref) async {
    final api = ref.read(apiClientProvider);
    _log.info('catalog api health check tap baseUrl=${api.config.baseUrlText}');
    final sw = Stopwatch()..start();
    try {
      final health = await api.health();
      _log.info(
        'catalog api health ok status=${health.status} '
        'version=${health.version} db=${health.db} '
        'in ${sw.elapsedMilliseconds}ms rid=${health.requestId}',
      );
      if (!context.mounted) return;
      showAppSnackbar(
        context,
        text:
            'Сервер ${health.status}, v${health.version}, rid=${health.requestId}',
      );
    } on ApiException catch (e) {
      _log.warning(
        'catalog api health failed in ${sw.elapsedMilliseconds}ms: $e',
      );
      if (!context.mounted) return;
      showAppSnackbar(
        context,
        text:
            '${apiErrorText(AppLocalizations.of(context), e)} rid=${e.requestId}',
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => AppButton(
    label: 'GET /health',
    size: AppButtonSize.m,
    type: AppButtonType.soft,
    onPressed: () => _check(context, ref),
  );
}

class _SyncCycleButton extends ConsumerWidget {
  const _SyncCycleButton();

  Future<void> _sync(BuildContext context, WidgetRef ref) async {
    _log.info('catalog sync tap → sync engine cycle reason=manual');
    final result = await ref.read(syncEngineProvider).sync(SyncReason.manual);
    _log.info('catalog sync finished $result');
    if (!context.mounted) return;
    showAppSnackbar(
      context,
      text: switch (result) {
        SyncCycleDone(:final push, :final pull) =>
          'Синхронизировано: отправлено ${push.applied}, '
              'отклонено ${push.rejected.length}, '
              'получено ${pull.counts.total}',
        SyncCycleFailed(:final error, :final retryIn) =>
          '${error is ApiException ? apiErrorText(AppLocalizations.of(context), error) : error.runtimeType}'
              '${retryIn == null ? '' : ', повтор через ${retryIn.inSeconds} с'}',
        SyncCycleSkipped(:final why) => 'Синхронизация пропущена: $why',
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => AppButton(
    label: 'Синхронизировать',
    size: AppButtonSize.m,
    type: AppButtonType.soft,
    onPressed: () => _sync(context, ref),
  );
}
