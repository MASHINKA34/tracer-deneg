import 'package:flutter/services.dart';
import 'package:shared/shared.dart';

final RegExp _separators = RegExp(r'[\s\-]');

String formatInviteCodeInput(String raw) {
  final upper = raw.toUpperCase();
  final prefixAt = upper.indexOf(inviteCodePrefix);
  final String tail;
  if (prefixAt >= 0) {
    tail = upper.substring(prefixAt + inviteCodePrefix.length);
  } else {
    final compact = upper.replaceAll(_separators, '');
    if (compact.isNotEmpty &&
        compact.length < inviteCodePrefix.length &&
        inviteCodePrefix.startsWith(compact)) {
      return compact;
    }
    tail = upper;
  }
  final body = StringBuffer();
  for (final char in tail.split('')) {
    if (body.length == inviteCodeLength) break;
    final mapped = switch (char) {
      'O' => '0',
      'I' || 'L' => '1',
      _ => char,
    };
    if (crockfordAlphabet.contains(mapped)) body.write(mapped);
  }
  if (body.isEmpty) return prefixAt >= 0 ? inviteCodePrefix : '';
  return '$inviteCodePrefix-$body';
}

int inviteCodeBodyLength(String text) {
  final at = text.indexOf('-');
  return at < 0 ? 0 : text.length - at - 1;
}

String? completeInviteCode(String text) =>
    inviteCodeBodyLength(text) == inviteCodeLength
    ? normalizeInviteCode(text)
    : null;

final class InviteCodeFormatter extends TextInputFormatter {
  const InviteCodeFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = formatInviteCodeInput(newValue.text);
    if (text == newValue.text) return newValue;
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
