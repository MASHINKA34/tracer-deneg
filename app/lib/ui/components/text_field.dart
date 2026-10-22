import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../icons/app_icon.dart';
import '../theme/app_text.dart';
import '../theme/app_theme.dart';
import '../tokens/tokens.g.dart';
import 'tap_target.dart';

/// Поле ввода (Figma TextField `3:252`): подпись сверху, поле 52 с иконкой
/// слева, «глазик» для пароля, подсказка или ошибка снизу.
///
/// Состояние Default / Focused / Error определяется само: фокус — по
/// клавиатуре, ошибка — [error] или заданный [errorText] (рамка `status/danger`;
/// текст под полем, если он есть, тоже красный — как в Figma, где «Состояние»
/// и «Показать подсказку» — отдельные свойства).
/// «Глазик»: пароль скрыт — `eye` цвета `text/tertiary`, виден — та же
/// иконка цвета `accent-strong` (в Figma нет перечёркнутого глаза; решение
/// этапа 03).
class AppTextField extends StatefulWidget {
  const AppTextField({
    super.key,
    required this.label,
    this.placeholder,
    this.controller,
    this.focusNode,
    this.icon,
    this.password = false,
    this.helperText,
    this.error = false,
    this.errorText,
    this.keyboardType,
    this.textInputAction,
    this.inputFormatters,
    this.autofocus = false,
    this.enabled = true,
    this.readOnly = false,
    this.onTap,
    this.onChanged,
    this.onSubmitted,
  });

  /// Подпись над полем («Логин»).
  final String label;

  /// Текст-заглушка в пустом поле («Придумай логин»).
  final String? placeholder;
  final TextEditingController? controller;
  final FocusNode? focusNode;

  /// Иконка слева (свойство «Иконка слева»).
  final AppIcons? icon;

  /// Поле пароля: текст скрыт, справа «глазик».
  final bool password;

  /// Подсказка под полем (свойство «Подсказка»).
  final String? helperText;

  /// Состояние Error (рамка `status/danger`), даже без текста ошибки.
  final bool error;

  /// Текст ошибки под полем (вместо подсказки); включает состояние Error.
  final String? errorText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final bool autofocus;
  final bool enabled;
  final bool readOnly;
  final VoidCallback? onTap;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  FocusNode? _ownFocus;
  bool _focused = false;
  bool _revealed = false;

  FocusNode get _focus => widget.focusNode ?? (_ownFocus ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
  }

  @override
  void didUpdateWidget(AppTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      (oldWidget.focusNode ?? _ownFocus)?.removeListener(_onFocus);
      _focus.addListener(_onFocus);
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    _ownFocus?.dispose();
    super.dispose();
  }

  void _onFocus() {
    if (_focused != _focus.hasFocus) setState(() => _focused = _focus.hasFocus);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final mood = context.mood;
    final l10n = AppLocalizations.of(context);
    final error = widget.error || widget.errorText != null;
    final active = _focused || error;

    final Color background = active ? colors.bgSurface : colors.bgSurface2;
    final Border? border = error
        ? Border.all(color: colors.statusDanger, width: 2)
        : _focused
        ? Border.all(color: mood.accentStrong, width: 2)
        : null;
    final iconColor = _focused && !error
        ? mood.accentStrong
        : colors.textTertiary;
    final eyeColor = _revealed ? mood.accentStrong : colors.textTertiary;
    final valueStyle = AppText.bodyL.copyWith(color: colors.textPrimary);

    final field = TextField(
      controller: widget.controller,
      focusNode: _focus,
      obscureText: widget.password && !_revealed,
      enableSuggestions: !widget.password,
      autocorrect: !widget.password,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      inputFormatters: widget.inputFormatters,
      autofocus: widget.autofocus,
      enabled: widget.enabled,
      readOnly: widget.readOnly,
      showCursor: widget.readOnly ? false : null,
      enableInteractiveSelection: !widget.readOnly,
      onTap: widget.onTap,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      style: valueStyle,
      cursorColor: mood.accent,
      decoration: InputDecoration(
        isCollapsed: true,
        border: InputBorder.none,
        hintText: widget.placeholder,
        hintStyle: valueStyle.copyWith(color: colors.textTertiary),
      ),
    );

    // Строка поля по Figma: отступы 16, зазор 12, иконки 20. Вертикальный
    // отступ 15 даёт 52 при шрифте 1.0 и рост при крупном.
    final box = Container(
      constraints: const BoxConstraints(minHeight: 52),
      // Рамка 2 в Figma «внутри»: по горизонтали сдвигает содержимое на 2
      // (Container добавляет толщину рамки к отступу), а высота поля
      // остаётся 52 — поэтому вертикальный отступ уменьшаем на рамку.
      padding: EdgeInsets.symmetric(
        horizontal: 16,
        vertical: border == null ? 15 : 13,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(RadiusTokens.md),
        border: border,
      ),
      child: Row(
        children: [
          if (widget.icon != null) ...[
            AppIcon(widget.icon!, size: 20, color: iconColor),
            const SizedBox(width: 12),
          ],
          Expanded(child: field),
          if (widget.password) ...[
            const SizedBox(width: 12),
            AppIcon(AppIcons.eye, size: 20, color: eyeColor),
          ],
        ],
      ),
    );

    final under = widget.errorText ?? widget.helperText;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          widget.label,
          style: AppText.labelS.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: 6),
        if (!widget.password)
          box
        else
          Stack(
            children: [
              box,
              // Область нажатия «глазика» 48 dp поверх строки: рисунок
              // остаётся на месте (16 от края), нажатие ловится шире.
              Positioned(
                top: 0,
                bottom: 0,
                right: 2 + (border == null ? 0 : 2),
                child: Semantics(
                  button: true,
                  label: _revealed
                      ? l10n.a11yHidePassword
                      : l10n.a11yShowPassword,
                  child: TapTarget(
                    child: InkResponse(
                      radius: 22,
                      onTap: widget.enabled
                          ? () => setState(() => _revealed = !_revealed)
                          : null,
                      child: const SizedBox(width: 48, height: 48),
                    ),
                  ),
                ),
              ),
            ],
          ),
        if (under != null) ...[
          const SizedBox(height: 6),
          Text(
            under,
            style: AppText.caption.copyWith(
              color: error ? colors.statusDanger : colors.textTertiary,
            ),
          ),
        ],
      ],
    );
  }
}
