import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/components/fitting_text.dart';
import '../../ui/components/sheet.dart';
import '../../ui/components/text_field.dart';
import '../../ui/theme/app_text.dart';
import '../../ui/theme/app_theme.dart';

final _log = Logger('categories');

String? lastEmojiOf(String text) {
  final value = normalizeText(text);
  if (value.isEmpty) return null;
  final last = value.characters.last;
  return validateEmoji(last) == null ? last : null;
}

Future<String?> showCategoryEmojiSheet(
  BuildContext context, {
  String? hint,
}) async {
  final sw = Stopwatch()..start();
  final root = Navigator.of(context, rootNavigator: true);
  _log.fine('emoji sheet opened: text field with the system keyboard');
  final result = await showAppSheet<String>(
    root.context,
    builder: (context) => [CategoryEmojiSheet(hint: hint)],
  );
  if (result == null) {
    _log.fine(
      'emoji sheet closed without emoji after ${sw.elapsedMilliseconds}ms: '
      'back gesture, tap outside or swipe down, emoji stays',
    );
  } else {
    _log.fine('emoji sheet picked an emoji after ${sw.elapsedMilliseconds}ms');
  }
  return result;
}

class CategoryEmojiSheet extends StatefulWidget {
  const CategoryEmojiSheet({super.key, this.hint});

  final String? hint;

  @override
  State<CategoryEmojiSheet> createState() => _CategoryEmojiSheetState();
}

class _CategoryEmojiSheetState extends State<CategoryEmojiSheet> {
  final TextEditingController _text = TextEditingController();
  bool _invalid = false;
  bool _picked = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    if (_picked) return;
    final value = normalizeText(text);
    if (value.isEmpty) {
      if (_invalid) setState(() => _invalid = false);
      return;
    }
    final emoji = lastEmojiOf(value);
    if (emoji != null) {
      _picked = true;
      _log.fine(
        'emoji sheet input length=${textLength(value)} ends with an emoji → '
        'applying it and closing',
      );
      Navigator.of(context).pop(emoji);
      return;
    }
    final error = validateEmoji(value.characters.last);
    _log.fine(
      'emoji sheet input rejected: ${error?.code} length=${textLength(value)}',
    );
    if (!_invalid) setState(() => _invalid = true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final media = MediaQuery.of(context);
    final keyboard = math.max(
      0.0,
      media.viewInsets.bottom - media.viewPadding.bottom,
    );
    return Flexible(
      child: Padding(
        padding: EdgeInsets.only(bottom: keyboard),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: FittingText(
                  l10n.categoryEmojiSheetTitle,
                  style: AppText.titleM.copyWith(color: colors.textPrimary),
                ),
              ),
              const SizedBox(height: 16),
              AppTextField(
                label: l10n.categoryEmoji,
                controller: _text,
                autofocus: true,
                keyboardType: TextInputType.text,
                textInputAction: TextInputAction.done,
                errorText: _invalid ? l10n.categoryEmojiInvalid : null,
                onChanged: _onChanged,
              ),
              const SizedBox(height: 12),
              Text(
                widget.hint ?? l10n.categoryEmojiSheetHint,
                style: AppText.caption.copyWith(color: colors.textTertiary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
