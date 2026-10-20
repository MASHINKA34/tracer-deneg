import 'package:drift/drift.dart';
import 'package:drift/isolate.dart' show DriftRemoteException;
import 'package:drift/native.dart';

final RegExp _parametersTail = RegExp(r', parameters: .*$', dotAll: true);

Object redactDbError(Object error) => switch (error) {
  SqliteException() => SqliteException(
    extendedResultCode: error.extendedResultCode,
    message: error.message,
    explanation: error.explanation,
    causingStatement: error.causingStatement,
    parametersToStatement: error.parametersToStatement == null
        ? null
        : [
            for (final p in error.parametersToStatement!)
              _HiddenParameter.of(p),
          ],
    operation: error.operation,
    offset: error.offset,
  ),
  DriftRemoteException(:final remoteCause) => redactDbError(remoteCause),
  CouldNotRollBackException() => CouldNotRollBackException(
    redactDbError(error.cause),
    error.originalStackTrace,
    redactDbError(error.exception),
  ),
  DriftWrappedException(:final cause) => DriftWrappedException(
    message: error.message,
    cause: cause == null ? null : redactDbError(cause),
    trace: error.trace,
  ),
  FormatException(source: Object()) => FormatException(
    error.message,
    null,
    error.offset,
  ),
  String() => error.replaceFirst(_parametersTail, ', parameters: <hidden>'),
  _ => error,
};

final class _HiddenParameter {
  const _HiddenParameter(this.kind);

  factory _HiddenParameter.of(Object? value) =>
      _HiddenParameter(switch (value) {
        null => 'null',
        String() => 'text:${value.length}',
        int() || BigInt() => 'int',
        double() => 'real',
        bool() => 'bool',
        Uint8List() => 'blob:${value.length}',
        _ => value.runtimeType.toString(),
      });

  final String kind;

  @override
  String toString() => '<$kind>';
}
