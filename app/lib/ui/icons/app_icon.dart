import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:logging/logging.dart';
import 'package:shared/logging.dart';

final _log = Logger('icons');

/// Иконки из Figma (`icon/*`, 24×24, обводка 2) — `assets/icons/<name>.svg`.
/// Экспортированы через Figma MCP без правок; цвет задаёт [AppIcon].
enum AppIcons {
  alertCircle('alert-circle'),
  arrowLeft('arrow-left'),
  backspace('backspace'),
  bell('bell'),
  calendar('calendar'),
  check('check'),
  chevronDown('chevron-down'),
  chevronLeft('chevron-left'),
  chevronRight('chevron-right'),
  cloudCheck('cloud-check'),
  cloudOff('cloud-off'),
  copy('copy'),
  download('download'),
  eye('eye'),
  filter('filter'),
  link('link'),
  lock('lock'),
  logOut('log-out'),
  message('message'),
  moon('moon'),
  more('more'),
  pencil('pencil'),
  pieChart('pie-chart'),
  plus('plus'),
  refresh('refresh'),
  repeat('repeat'),
  search('search'),
  share('share'),
  tag('tag'),
  trash('trash'),
  trendingDown('trending-down'),
  user('user'),
  users('users'),
  wallet('wallet'),
  x('x');

  const AppIcons(this.figmaName);

  /// Имя в Figma без префикса `icon/`.
  final String figmaName;

  String get asset => 'assets/icons/$figmaName.svg';
}

/// Иконка [icon] размером [size] цвета [color] (одноцветная: весь рисунок
/// перекрашивается). Без [semanticLabel] скрыта от TalkBack — подпись
/// даёт кнопка, в которой она стоит.
///
/// Обводка — [strokeWidth] пикселей экрана при любом размере, как у
/// экземпляров иконок в Figma (там рисунок масштабируется, а обводка
/// остаётся 2; у «+» на кнопке Fab — 2,6).
class AppIcon extends StatelessWidget {
  const AppIcon(
    this.icon, {
    super.key,
    this.size = 24,
    required this.color,
    this.strokeWidth = 2,
    this.semanticLabel,
  });

  final AppIcons icon;
  final double size;
  final Color color;
  final double strokeWidth;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return SvgPicture(
      _IconLoader(icon.asset, viewBoxStroke: strokeWidth * _viewBox / size),
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      semanticsLabel: semanticLabel,
      excludeFromSemantics: semanticLabel == null,
      errorBuilder: (context, error, stackTrace) {
        _log.severe(
          'icon load failed asset=${icon.asset}: ${describeError(error)}',
          error,
          stackTrace,
        );
        return SizedBox.square(dimension: size);
      },
    );
  }
}

/// Размер viewBox у всех иконок Figma.
const double _viewBox = 24;

/// Загрузчик иконки: та же SVG, но обводка пересчитана в единицы viewBox,
/// чтобы на экране она была заданной толщины при любом размере иконки.
class _IconLoader extends SvgAssetLoader {
  const _IconLoader(super.assetName, {required this.viewBoxStroke});

  final double viewBoxStroke;

  @override
  String provideSvg(ByteData? message) => super
      .provideSvg(message)
      .replaceAll('stroke-width="2"', 'stroke-width="$viewBoxStroke"');

  @override
  SvgCacheKey cacheKey(BuildContext? context) => SvgCacheKey(
    theme: getTheme(context),
    colorMapper: colorMapper,
    keyData: (assetName, viewBoxStroke),
  );

  @override
  int get hashCode => Object.hash(assetName, viewBoxStroke);

  @override
  bool operator ==(Object other) =>
      other is _IconLoader &&
      other.assetName == assetName &&
      other.viewBoxStroke == viewBoxStroke;
}
