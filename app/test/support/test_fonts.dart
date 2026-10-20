import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Семейство, под которым в тестах загружен цветной эмодзи-шрифт Windows.
const String testEmojiFamily = 'Segoe UI Emoji';

/// Путь к эмодзи-шрифту Windows (в репозиторий не кладём — ответ
/// пользователя на этапе 03).
const String _windowsEmojiFont = r'C:\Windows\Fonts\seguiemj.ttf';

bool _loaded = false;

/// Загружает в тестовый движок настоящие шрифты приложения (все семейства
/// из `FontManifest.json`: Manrope, Unbounded) и эмодзи Segoe UI Emoji.
/// Без этого `flutter test` рисует весь текст тестовым шрифтом-заглушкой.
Future<void> loadTestFonts() async {
  if (_loaded) return;
  TestWidgetsFlutterBinding.ensureInitialized();
  final manifest = jsonDecode(
    await rootBundle.loadString('FontManifest.json'),
  ) as List<Object?>;
  for (final entry in manifest.cast<Map<String, Object?>>()) {
    final family = entry['family']! as String;
    final loader = FontLoader(family);
    for (final font
        in (entry['fonts']! as List<Object?>).cast<Map<String, Object?>>()) {
      loader.addFont(rootBundle.load(font['asset']! as String));
    }
    await loader.load();
  }
  final emoji = File(_windowsEmojiFont);
  if (emoji.existsSync()) {
    final bytes = emoji.readAsBytesSync();
    final loader = FontLoader(testEmojiFamily)
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
  }
  _loaded = true;
}
