import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared/shared.dart';

final _log = Logger('export');

const String exportFolder = 'export';

const String csvMimeType = 'text/csv';

typedef ExportDirectory = Future<Directory> Function();

Future<Directory> exportCacheDirectory() async {
  final cache = await getTemporaryDirectory();
  return Directory('${cache.path}${Platform.pathSeparator}$exportFolder');
}

String _nameOf(FileSystemEntity entity) =>
    entity.uri.pathSegments.lastWhere((s) => s.isNotEmpty, orElse: () => '');

final class ExportFiles {
  ExportFiles(this._directory);

  final ExportDirectory _directory;

  Future<File> write(String name, List<int> bytes) async {
    final sw = Stopwatch()..start();
    final Directory dir;
    try {
      dir = await _directory();
    } catch (e, st) {
      _log.severe(
        'export cache folder unavailable, file not written '
        'size=${bytes.length}B after ${sw.elapsedMilliseconds}ms: '
        '${describeError(e)}',
        e,
        st,
      );
      rethrow;
    }
    await _deletePrevious(dir);
    final file = File('${dir.path}${Platform.pathSeparator}$name');
    try {
      await dir.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
    } catch (e, st) {
      _log.severe(
        'export file write failed path=${file.path} size=${bytes.length}B '
        'after ${sw.elapsedMilliseconds}ms: ${describeError(e)}',
        e,
        st,
      );
      rethrow;
    }
    _log.fine(
      'export file written to ${dir.path} size=${bytes.length}B '
      'in ${sw.elapsedMilliseconds}ms',
    );
    return file;
  }

  Future<void> _deletePrevious(Directory dir) async {
    final sw = Stopwatch()..start();
    final List<FileSystemEntity> previous;
    try {
      if (!await dir.exists()) {
        _log.fine(
          'export folder ${dir.path} does not exist yet, no previous file '
          'to delete',
        );
        return;
      }
      previous = await dir.list().toList();
    } catch (e, st) {
      _log.warning(
        'export folder ${dir.path} listing failed, previous file not '
        'deleted, writing anyway: ${describeError(e)}',
        e,
        st,
      );
      return;
    }
    if (previous.isEmpty) {
      _log.fine('export folder ${dir.path} is empty, nothing to delete');
      return;
    }
    var deleted = 0;
    for (final entity in previous) {
      try {
        final size = entity is File ? await entity.length() : null;
        await entity.delete(recursive: true);
        deleted++;
        _log.fine(
          'previous export file deleted name=${_nameOf(entity)} '
          'size=${size == null ? '-' : '${size}B'}',
        );
      } catch (e, st) {
        _log.warning(
          'previous export file delete failed path=${entity.path}, '
          'writing the new one anyway: ${describeError(e)}',
          e,
          st,
        );
      }
    }
    _log.fine(
      'export folder cleaned deleted=$deleted of ${previous.length} '
      'in ${sw.elapsedMilliseconds}ms',
    );
  }
}

abstract interface class ExportSharer {
  Future<ShareResult> share(File file);
}

final class SharePlusExportSharer implements ExportSharer {
  const SharePlusExportSharer();

  @override
  Future<ShareResult> share(File file) => SharePlus.instance.share(
    ShareParams(files: [XFile(file.path, mimeType: csvMimeType)]),
  );
}

final exportFilesProvider = Provider<ExportFiles>(
  (ref) => ExportFiles(exportCacheDirectory),
  name: 'exportFiles',
);

final exportSharerProvider = Provider<ExportSharer>(
  (ref) => const SharePlusExportSharer(),
  name: 'exportSharer',
);
