import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:shared/logging.dart';

final _log = Logger('fonts');

/// Итог проверки шрифтов: сколько файлов прочитано и какие не открылись.
final class FontCheckResult {
  const FontCheckResult(this.loaded, this.failed);

  final int loaded;

  /// `семейство → файл` для каждого шрифта, который не прочитался.
  final List<String> failed;
}

/// Проверяет, что файлы шрифтов из `FontManifest.json` есть в сборке и
/// читаются. Сами шрифты из pubspec загружает движок, и Dart об их ошибке
/// не узнаёт — поэтому при запуске читаем каждый файл и пишем `error` с
/// именем ассета, если он не открылся (иначе текст молча рисовался бы
/// системным шрифтом).
Future<FontCheckResult> checkFontAssets(AssetBundle bundle) async {
  final sw = Stopwatch()..start();
  final List<Object?> manifest;
  try {
    manifest = jsonDecode(
      await bundle.loadString('FontManifest.json'),
    ) as List<Object?>;
  } catch (e, st) {
    _log.severe(
      'font manifest unreadable asset=FontManifest.json: ${describeError(e)}',
      e,
      st,
    );
    return const FontCheckResult(0, ['FontManifest.json']);
  }
  var loaded = 0;
  final failed = <String>[];
  for (final entry in manifest.cast<Map<String, Object?>>()) {
    final family = entry['family'] as String? ?? '?';
    for (final font
        in (entry['fonts'] as List<Object?>? ?? const [])
            .cast<Map<String, Object?>>()) {
      final asset = font['asset'] as String? ?? '?';
      try {
        final data = await bundle.load(asset);
        loaded++;
        _log.fine(
          'font asset ok family=$family asset=$asset bytes=${data.lengthInBytes}',
        );
      } catch (e, st) {
        failed.add('$family → $asset');
        _log.severe(
          'font asset load failed family=$family asset=$asset: '
          '${describeError(e)}',
          e,
          st,
        );
      }
    }
  }
  if (failed.isEmpty) {
    _log.info('fonts ok: $loaded files in ${sw.elapsedMilliseconds}ms');
  } else {
    _log.severe(
      'fonts check: ${failed.length} of ${loaded + failed.length} files failed '
      'in ${sw.elapsedMilliseconds}ms',
    );
  }
  return FontCheckResult(loaded, failed);
}
