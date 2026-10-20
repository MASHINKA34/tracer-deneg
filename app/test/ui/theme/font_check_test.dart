import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/ui/theme/font_check.dart';

/// Набор ассетов, в котором одного файла шрифта нет.
class _BundleWithMissingFont extends CachingAssetBundle {
  _BundleWithMissingFont(this.real);

  final AssetBundle real;

  @override
  Future<ByteData> load(String key) {
    if (key.endsWith('Manrope-Bold.ttf')) {
      throw StateError('Unable to load asset: "$key".');
    }
    return real.load(key);
  }

  @override
  Future<String> loadString(String key, {bool cache = true}) async =>
      utf8.decode((await real.load(key)).buffer.asUint8List());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<LogRecord> records;
  late StreamSubscription<LogRecord> sub;

  setUp(() {
    records = [];
    Logger.root.level = Level.ALL;
    sub = Logger.root.onRecord.listen(records.add);
  });
  tearDown(() => sub.cancel());

  test('все шрифты приложения есть в сборке', () async {
    final result = await checkFontAssets(rootBundle);
    expect(result.failed, isEmpty);
    // Manrope × 4 + Unbounded + MaterialIcons (uses-material-design).
    expect(result.loaded, 6);
    expect(
      records.map((r) => r.message),
      contains(startsWith('fonts ok: 6 files')),
    );
  });

  test('файла нет — error с семейством и именем ассета', () async {
    final result = await checkFontAssets(_BundleWithMissingFont(rootBundle));
    expect(result.failed, ['Manrope → assets/fonts/manrope/Manrope-Bold.ttf']);
    final errors = records
        .where((r) => r.level == Level.SEVERE)
        .map((r) => r.message);
    expect(
      errors,
      contains(
        startsWith(
          'font asset load failed family=Manrope '
          'asset=assets/fonts/manrope/Manrope-Bold.ttf',
        ),
      ),
    );
  });
}
