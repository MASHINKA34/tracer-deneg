/// Генератор `lib/ui/tokens/tokens.g.dart` из `tool/design-tokens.json`.
///
/// Запуск из папки `app`:
///   dart run tool/gen_tokens.dart          — перегенерировать файл
///   dart run tool/gen_tokens.dart --check  — только проверить, что файл
///                                            совпадает с JSON (для check.ps1)
/// Уровень логов — переменная окружения `LOG_LEVEL` (debug|info|warn|error).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:shared/logging.dart';
import 'package:shared/logging_io.dart';

import 'src/token_codegen.dart';

final _log = Logger('tokens');

Future<void> main(List<String> args) async {
  registerIoErrorDetails();
  final parsedLevel = parseLogLevel(Platform.environment['LOG_LEVEL']);
  Logger.root.level = parsedLevel ?? Level.INFO;
  Logger.root.onRecord.listen((record) {
    final line = formatLogRecord(record);
    if (record.level >= Level.WARNING) {
      stderr.writeln(line);
    } else {
      stdout.writeln(line);
    }
  });

  try {
    exitCode = await _run(args);
  } catch (e, st) {
    _log.severe('gen_tokens crashed: ${describeError(e)}', e, st);
    exitCode = 2;
  }
  await stdout.flush();
  await stderr.flush();
}

Future<int> _run(List<String> args) async {
  final total = Stopwatch()..start();
  final unknown = args.where((a) => a != '--check').toList();
  if (unknown.isNotEmpty) {
    _log.severe('unknown arguments: ${unknown.join(' ')} (allowed: --check)');
    return 64;
  }
  final check = args.contains('--check');
  final appDir = File.fromUri(Platform.script).parent.parent;
  final input = File.fromUri(appDir.uri.resolve('tool/design-tokens.json'));
  final output = File.fromUri(
    appDir.uri.resolve('lib/ui/tokens/tokens.g.dart'),
  );
  _log.info(
    'gen_tokens started mode=${check ? 'check' : 'write'} '
    'input=${input.path} output=${output.path} '
    'log=${logLevelName(Logger.root.level)}',
  );

  // 1. Чтение JSON.
  var sw = Stopwatch()..start();
  final String text;
  try {
    text = await input.readAsString();
  } on FileSystemException catch (e, st) {
    _log.severe('cannot read ${input.path}: ${describeError(e)}', e, st);
    return 1;
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException catch (e) {
    _log.severe(
      'invalid JSON in ${input.path} at offset ${e.offset}: ${e.message}',
    );
    return 1;
  }
  if (decoded is! Map<String, Object?>) {
    _log.severe('${input.path}: top level must be an object');
    return 1;
  }
  _log.info(
    'read ${input.path}: ${text.length} chars, '
    'sections=${decoded.keys.where((k) => !k.startsWith('_')).join(',')} '
    'in ${sw.elapsedMilliseconds}ms',
  );

  // 2. Генерация.
  sw = Stopwatch()..start();
  final TokenCodegenResult result;
  try {
    result = generateTokens(decoded);
  } on TokenFormatException catch (e) {
    for (final error in e.errors) {
      _log.severe('token format error at ${error.path}: ${error.message}');
    }
    _log.severe(
      'generation failed: ${e.errors.length} format error(s) in ${input.path}',
    );
    return 1;
  }
  for (final skipped in result.stats.skipped) {
    _log.info('skipped $skipped');
  }
  _log.info('generated ${result.stats} in ${sw.elapsedMilliseconds}ms');

  // 3. dart format — файл должен совпадать с тем, что выдаст форматтер,
  // иначе `dart format .` ломал бы проверку --check.
  final formatted = await _format(appDir, result.source);
  if (formatted == null) return 1;

  // 4. Запись или проверка.
  final existing = await output.exists() ? await output.readAsString() : null;
  final lines = '\n'.allMatches(formatted).length;
  if (check) {
    if (existing == formatted) {
      _log.info(
        '${output.path} is up to date ($lines lines) '
        'in ${total.elapsedMilliseconds}ms',
      );
      return 0;
    }
    _log.severe(
      '${output.path} is ${existing == null ? 'missing' : 'out of date'}: '
      'run "dart run tool/gen_tokens.dart" in app/ and commit the result',
    );
    return 1;
  }
  if (existing == formatted) {
    _log.info(
      '${output.path} unchanged ($lines lines), not rewritten '
      'in ${total.elapsedMilliseconds}ms',
    );
    return 0;
  }
  await output.parent.create(recursive: true);
  await output.writeAsString(formatted);
  _log.info(
    'wrote ${output.path}: $lines lines, ${utf8.encode(formatted).length} bytes '
    '(${existing == null ? 'new file' : 'updated'}) '
    'in ${total.elapsedMilliseconds}ms',
  );
  return 0;
}

/// Прогоняет [source] через `dart format` (временный файл внутри пакета,
/// чтобы форматтер взял версию языка пакета). `null` — форматтер упал.
Future<String?> _format(Directory appDir, String source) async {
  final sw = Stopwatch()..start();
  final tmpDir = Directory.fromUri(
    appDir.uri.resolve('.dart_tool/gen_tokens/'),
  );
  final tmp = File.fromUri(tmpDir.uri.resolve('tokens.g.dart'));
  await tmpDir.create(recursive: true);
  await tmp.writeAsString(source);
  final dart = Platform.resolvedExecutable;
  _log.fine('running $dart format ${tmp.path}');
  final ProcessResult run;
  try {
    run = await Process.run(dart, ['format', tmp.path]);
  } on ProcessException catch (e, st) {
    _log.severe('cannot start dart format: ${describeError(e)}', e, st);
    return null;
  }
  if (run.exitCode != 0) {
    _log.severe(
      'dart format failed with exit code ${run.exitCode} '
      'in ${sw.elapsedMilliseconds}ms: ${run.stderr}${run.stdout}',
    );
    return null;
  }
  final formatted = await tmp.readAsString();
  await tmpDir.delete(recursive: true);
  final report = (run.stdout as String).trim().split(RegExp(r'\s*\n\s*'));
  _log.fine(
    'dart format done in ${sw.elapsedMilliseconds}ms: ${report.join('; ')}',
  );
  return formatted;
}
