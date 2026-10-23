import 'package:milionchik/data/session/secure_values.dart';

final class FakeSecureValues implements SecureValues {
  FakeSecureValues([Map<String, String>? data]) : data = data ?? {};

  final Map<String, String> data;
  Object? readError;
  Object? deleteError;
  String? failWriteOf;
  Object writeError = StateError('write failed');
  final List<String> operations = [];

  @override
  Future<String?> read(String key) async {
    operations.add('read $key');
    final error = readError;
    if (error != null) throw error;
    return data[key];
  }

  @override
  Future<void> write(String key, String value) async {
    operations.add('write $key');
    if (failWriteOf == key) throw writeError;
    data[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    operations.add('delete $key');
    final error = deleteError;
    if (error != null) throw error;
    data.remove(key);
  }
}
