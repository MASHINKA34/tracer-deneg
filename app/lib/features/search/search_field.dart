import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/components/tap_target.dart';
import '../../ui/icons/app_icon.dart';
import '../../ui/theme/app_text.dart';
import '../../ui/theme/app_theme.dart';

class SearchField extends StatefulWidget {
  const SearchField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;

  static const double height = 44;

  static const double _border = 2;

  static const double _clearCenterFromEnd = 21;

  static const double endInset = 12;

  @override
  State<SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<SearchField> {
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focused = widget.focusNode.hasFocus;
    widget.focusNode.addListener(_onFocus);
    widget.controller.addListener(_onText);
  }

  @override
  void didUpdateWidget(SearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_onFocus);
      widget.focusNode.addListener(_onFocus);
    }
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onText);
      widget.controller.addListener(_onText);
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocus);
    widget.controller.removeListener(_onText);
    super.dispose();
  }

  void _onFocus() {
    if (_focused != widget.focusNode.hasFocus) {
      setState(() => _focused = widget.focusNode.hasFocus);
    }
  }

  void _onText() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final mood = context.mood;
    final style = AppText.bodyL.copyWith(color: colors.textPrimary);
    final hasText = widget.controller.text.isNotEmpty;

    final field = Container(
      constraints: const BoxConstraints(minHeight: SearchField.height),
      padding: const EdgeInsets.fromLTRB(14, 9, 10, 9),
      decoration: ShapeDecoration(
        color: _focused ? colors.bgSurface : colors.bgSurface2,
        shape: StadiumBorder(
          side: _focused
              ? BorderSide(color: mood.accentStrong, width: SearchField._border)
              : BorderSide(
                  color: colors.bgSurface2,
                  width: SearchField._border,
                ),
        ),
      ),
      child: Row(
        children: [
          AppIcon(AppIcons.search, size: 20, color: colors.textTertiary),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: widget.focusNode,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onChanged: widget.onChanged,
              onSubmitted: widget.onSubmitted,
              style: style,
              cursorColor: mood.accent,
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: l10n.searchTitle,
                hintStyle: style.copyWith(color: colors.textTertiary),
              ),
            ),
          ),
          if (hasText) ...[
            const SizedBox(width: 8),
            AppIcon(AppIcons.x, size: 18, color: colors.textTertiary),
          ],
        ],
      ),
    );

    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.only(
            top: (kMinTapTarget - SearchField.height) / 2,
            bottom: (kMinTapTarget - SearchField.height) / 2,
            right: SearchField.endInset,
          ),
          child: field,
        ),
        if (hasText)
          Positioned(
            top: 0,
            bottom: 0,
            right:
                SearchField.endInset +
                SearchField._clearCenterFromEnd -
                kMinTapTarget / 2,
            width: kMinTapTarget,
            child: Semantics(
              button: true,
              label: l10n.searchClear,
              excludeSemantics: true,
              onTap: widget.onClear,
              child: InkResponse(
                radius: 22,
                onTap: widget.onClear,
                child: const SizedBox.expand(),
              ),
            ),
          ),
      ],
    );
  }
}
